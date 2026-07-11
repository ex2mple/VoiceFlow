import AppKit
import VoiceFlowCore

/// The dictation state machine: hotkey press → record → release →
/// transcribe → clean → paste. All UI callbacks fire on the main queue.
final class DictationCoordinator {
    enum State: Equatable {
        case loadingModel
        case downloadingModel(percent: Int)
        case idle
        case recording
        case processing
        case failed(String)
    }

    private(set) var state: State = .loadingModel {
        didSet { for observer in stateObservers { observer(state) } }
    }
    private var stateObservers: [(State) -> Void] = []
    /// Short message worth flashing near the menu bar icon ("вставлено без чистки" etc).
    var onNotice: ((String) -> Void)?
    /// Live microphone RMS while recording (main queue) — feeds the HUD waveform.
    var onAudioLevel: ((Float) -> Void)?
    /// Partial transcript while the user is still speaking (main queue).
    var onPreview: ((String) -> Void)?

    func addStateObserver(_ observer: @escaping (State) -> Void) {
        stateObservers.append(observer)
        observer(state)
    }

    let history = HistoryStore()
    let stats = StatsStore()
    private let recorder = AudioRecorder()
    private let ollama = OllamaClient()
    private var whisper: WhisperEngine?
    private let whisperQueue = DispatchQueue(label: "voiceflow.whisper")
    private var previewTimer: Timer?
    private var previewBusy = false
    /// What we've already typed into the focused app in "cursor" live mode.
    private var typedPreview = ""
    /// Hands-free: a quick tap (< this) keeps recording until the next press.
    private let tapThreshold: TimeInterval = 0.35
    private var pressedAt: Date?
    private var autoStopTimer: Timer?
    /// Safety net for hands-free mode — stop after 3 minutes.
    private let maxRecordingSeconds: TimeInterval = 180
    /// User dictionary, reloaded at the start of each recording.
    private var dictionaryWords: [String] = []
    private var whisperPrompt: String?
    /// true when the session was started with the translate hotkey.
    private var sessionIsTranslate = false
    /// Preview transcribes at most this much of the tail — keeps each pass
    /// fast even during very long dictations.
    private let previewWindowSeconds: Double = 25

    // MARK: - Startup

    func bootstrap() {
        recorder.onLevel = { [weak self] level in self?.onAudioLevel?(level) }
        setupAI()
        if ModelLocator.modelExists {
            loadModel()
        } else {
            state = .downloadingModel(percent: 0)
            ModelDownloader().download(
                onProgress: { [weak self] p in self?.state = .downloadingModel(percent: p) },
                onDone: { [weak self] result in
                    switch result {
                    case .success: self?.loadModel()
                    case .failure(let e):
                        self?.state = .failed("Не скачалась модель: \(e.localizedDescription)")
                    }
                })
        }
    }

    private func loadModel() {
        state = .loadingModel
        whisperQueue.async { [weak self] in
            do {
                let engine = try WhisperEngine(modelPath: ModelLocator.modelPath().path)
                DispatchQueue.main.async {
                    self?.whisper = engine
                    self?.state = .idle
                }
            } catch {
                DispatchQueue.main.async {
                    self?.state = .failed("\(error)")
                }
            }
        }
    }

    // MARK: - Hotkey

    func hotkeyPressed(translate: Bool = false) {
        // Second press while a hands-free recording runs = «стоп».
        if state == .recording {
            finishRecording()
            return
        }
        guard state == .idle, whisper != nil else { return }
        sessionIsTranslate = translate
        guard Permissions.microphoneGranted else {
            Permissions.requestMicrophone { [weak self] granted in
                if !granted { self?.onNotice?("Нет доступа к микрофону") }
            }
            return
        }
        do {
            try recorder.start()
            state = .recording
            playSound("Tink")
            typedPreview = ""
            dictionaryWords = DictionaryFile.words()
            whisperPrompt = UserDictionary.whisperPrompt(dictionaryWords)
            pressedAt = Date()
            startPreviewLoop()
            autoStopTimer = Timer.scheduledTimer(
                withTimeInterval: maxRecordingSeconds, repeats: false
            ) { [weak self] _ in
                self?.finishRecording()
            }
        } catch {
            onNotice?(error.localizedDescription)
        }
    }

    func hotkeyReleased() {
        guard state == .recording else { return }
        // Quick tap → hands-free: recording continues until the next press.
        if let pressedAt, Date().timeIntervalSince(pressedAt) < tapThreshold {
            return
        }
        finishRecording()
    }

    private func finishRecording() {
        guard state == .recording else { return }
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        pressedAt = nil
        stopPreviewLoop()
        let samples = recorder.stop()
        guard AudioGate.shouldTranscribe(samples: samples, sampleRate: AudioRecorder.sampleRate) else {
            DebugLog.log("gate: REJECTED (silence or too short)")
            state = .idle
            return
        }
        DebugLog.log("gate: passed")
        state = .processing
        startProcessingWatchdog()
        process(AudioGain.normalized(samples))
    }

    /// Belt-and-braces: if the pipeline ever hangs (network died mid-request
    /// during sleep, etc.), unstick the state machine so the hotkey works again.
    private var watchdog: Timer?

    private func startProcessingWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            guard let self, self.state == .processing else { return }
            self.state = .idle
            self.onNotice?("Обработка зависла — сброшено")
        }
    }

    /// Called on wake from sleep: recover from any half-dead state.
    func recoverAfterWake() {
        if state == .recording {
            // The audio engine rarely survives sleep; drop the session.
            _ = recorder.stop()
            stopPreviewLoop()
            autoStopTimer?.invalidate()
            state = .idle
        }
    }

    private func playSound(_ name: String) {
        guard AppSettings.soundsEnabled else { return }
        let sound = NSSound(named: name)
        sound?.volume = 0.35
        sound?.play()
    }

    // MARK: - Live preview

    private func startPreviewLoop() {
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.previewTick()
        }
    }

    private func stopPreviewLoop() {
        previewTimer?.invalidate()
        previewTimer = nil
    }

    private func previewTick() {
        guard state == .recording, !previewBusy, whisper != nil else { return }
        let target = AppSettings.liveTextTarget
        var samples = recorder.snapshot()
        if target == .hud {
            // The capsule only shows the tail anyway; keep each pass fast.
            let window = Int(previewWindowSeconds * AudioRecorder.sampleRate)
            if samples.count > window { samples = Array(samples.suffix(window)) }
        }
        // In cursor mode the whole buffer is transcribed every time: the
        // typed text is diffed against the previous pass, so the prefix
        // must stay stable.
        guard AudioGate.shouldTranscribe(samples: samples, sampleRate: AudioRecorder.sampleRate)
        else { return }

        previewBusy = true
        whisperQueue.async { [weak self] in
            guard let self, let whisper = self.whisper else { return }
            defer { DispatchQueue.main.async { self.previewBusy = false } }
            // The user may have released the key while this job sat in the
            // queue — don't waste the final pass's turn on a stale preview.
            guard self.state == .recording else { return }
            let text = TranscriptSanitizer.clean(
                whisper.transcribe(AudioGain.normalized(samples), prompt: self.whisperPrompt))
            guard !text.isEmpty else { return }
            DispatchQueue.main.async {
                guard self.state == .recording else { return }
                switch target {
                case .hud:
                    self.onPreview?(text)
                case .cursor:
                    KeyTyper.retype(from: self.typedPreview, to: text)
                    self.typedPreview = text
                }
            }
        }
    }

    // MARK: - Pipeline

    private func process(_ samples: [Float]) {
        let recordedSeconds = Double(samples.count) / AudioRecorder.sampleRate
        whisperQueue.async { [weak self] in
            guard let self, let whisper = self.whisper else { return }
            let raw = whisper.transcribe(samples, prompt: self.whisperPrompt)
            let transcript = TranscriptSanitizer.clean(raw)
            DebugLog.log("whisper: raw=\(raw.count) chars, clean=\(transcript.count): "
                + "«\(String(transcript.prefix(60)))»")
            guard !transcript.isEmpty else {
                DispatchQueue.main.async { self.state = .idle }
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let translate = self.sessionIsTranslate
                let cleanupEnabled = AppSettings.cleanupEnabled
                let result: CleanupResult
                if translate {
                    result = await TextTranslator(
                        client: self.ollama, model: AppSettings.ollamaModel
                    ).translate(transcript)
                } else if cleanupEnabled {
                    result = await TextCleaner(
                        client: self.ollama, model: AppSettings.ollamaModel,
                        vocabulary: self.dictionaryWords
                    ).clean(transcript)
                } else {
                    result = CleanupResult(text: transcript, wasCleaned: false)
                }
                await MainActor.run {
                    self.history.add(result.text)
                    self.stats.record(text: result.text, duration: recordedSeconds)
                    if self.typedPreview.isEmpty {
                        TextInserter.insert(result.text)
                    } else {
                        // The live preview is already in the field — morph it
                        // into the final cleaned text instead of pasting a copy.
                        KeyTyper.retype(from: self.typedPreview, to: result.text)
                        self.typedPreview = ""
                    }
                    self.playSound("Pop")
                    if translate && !result.wasCleaned {
                        self.onNotice?("Перевод не удался — вставлен оригинал")
                    } else if !translate && cleanupEnabled && !result.wasCleaned {
                        self.onNotice?("Вставлено без ИИ-чистки")
                    }
                    self.state = .idle
                }
            }
        }
    }

    // MARK: - AI setup

    /// nil когда всё готово; текст — что происходит (скачивание и т.п.).
    private var aiSetupStatus: String?
    private var aiPullRunning = false

    /// First launch UX: if Ollama runs but the model isn't pulled yet,
    /// download it ourselves — the user shouldn't need a terminal.
    private func setupAI() {
        Task { [weak self] in
            guard let self else { return }
            guard await self.ollama.isAvailable() else { return }
            let model = AppSettings.ollamaModel
            if await self.ollama.hasModel(model) {
                if AppSettings.cleanupEnabled {
                    await TextCleaner(client: self.ollama, model: model).warmUp()
                }
                return
            }
            guard !self.aiPullRunning else { return }
            self.aiPullRunning = true
            defer { self.aiPullRunning = false }
            await MainActor.run {
                self.aiSetupStatus = "Скачивается ИИ-модель…"
                self.onNotice?("Скачиваю ИИ-модель (~2.5 ГБ)…")
            }
            var lastShown = -5
            do {
                try await self.ollama.pull(model: model) { progress in
                    guard let pct = progress.percent, pct >= lastShown + 5 else { return }
                    lastShown = pct
                    DispatchQueue.main.async {
                        self.aiSetupStatus = "Скачивается ИИ-модель: \(pct)%"
                        self.onNotice?("ИИ-модель: \(pct)%")
                    }
                }
                await MainActor.run {
                    self.aiSetupStatus = nil
                    self.onNotice?("ИИ-чистка готова ✓")
                }
                await TextCleaner(client: self.ollama, model: model).warmUp()
            } catch {
                await MainActor.run {
                    self.aiSetupStatus = "ИИ-модель не скачалась"
                    self.onNotice?("Не удалось скачать ИИ-модель")
                }
            }
        }
    }

    // MARK: - Status for the menu

    struct AIStatus {
        let line: String
        let ollamaMissing: Bool
    }

    func aiStatus() async -> AIStatus {
        guard await ollama.isAvailable() else {
            return AIStatus(
                line: "ИИ-чистка выключена: нет Ollama",
                ollamaMissing: true)
        }
        if let status = aiSetupStatus {
            return AIStatus(line: status, ollamaMissing: false)
        }
        if await ollama.hasModel(AppSettings.ollamaModel) {
            return AIStatus(line: "Ollama ✓ (\(AppSettings.ollamaModel))", ollamaMissing: false)
        }
        // Ollama появилась после запуска (например, только что установили).
        setupAI()
        return AIStatus(line: "Готовлю ИИ-модель…", ollamaMissing: false)
    }
}
