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
    private let recorder = AudioRecorder()
    private let ollama = OllamaClient()
    private var whisper: WhisperEngine?
    private let whisperQueue = DispatchQueue(label: "voiceflow.whisper")
    private var previewTimer: Timer?
    private var previewBusy = false
    /// Preview transcribes at most this much of the tail — keeps each pass
    /// fast even during very long dictations.
    private let previewWindowSeconds: Double = 25

    // MARK: - Startup

    func bootstrap() {
        recorder.onLevel = { [weak self] level in self?.onAudioLevel?(level) }
        if AppSettings.cleanupEnabled {
            Task { [ollama] in
                await TextCleaner(client: ollama, model: AppSettings.ollamaModel).warmUp()
            }
        }
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

    func hotkeyPressed() {
        guard state == .idle, whisper != nil else { return }
        guard Permissions.microphoneGranted else {
            Permissions.requestMicrophone { [weak self] granted in
                if !granted { self?.onNotice?("Нет доступа к микрофону") }
            }
            return
        }
        do {
            try recorder.start()
            state = .recording
            startPreviewLoop()
        } catch {
            onNotice?(error.localizedDescription)
        }
    }

    func hotkeyReleased() {
        guard state == .recording else { return }
        stopPreviewLoop()
        let samples = recorder.stop()
        guard AudioGate.shouldTranscribe(samples: samples, sampleRate: AudioRecorder.sampleRate) else {
            state = .idle
            return
        }
        state = .processing
        process(samples)
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
        var samples = recorder.snapshot()
        let window = Int(previewWindowSeconds * AudioRecorder.sampleRate)
        if samples.count > window { samples = Array(samples.suffix(window)) }
        guard AudioGate.shouldTranscribe(samples: samples, sampleRate: AudioRecorder.sampleRate)
        else { return }

        previewBusy = true
        whisperQueue.async { [weak self] in
            guard let self, let whisper = self.whisper else { return }
            defer { DispatchQueue.main.async { self.previewBusy = false } }
            // The user may have released the key while this job sat in the
            // queue — don't waste the final pass's turn on a stale preview.
            guard self.state == .recording else { return }
            let text = TranscriptSanitizer.clean(whisper.transcribe(samples))
            guard !text.isEmpty else { return }
            DispatchQueue.main.async {
                guard self.state == .recording else { return }
                self.onPreview?(text)
            }
        }
    }

    // MARK: - Pipeline

    private func process(_ samples: [Float]) {
        whisperQueue.async { [weak self] in
            guard let self, let whisper = self.whisper else { return }
            let raw = whisper.transcribe(samples)
            let transcript = TranscriptSanitizer.clean(raw)
            guard !transcript.isEmpty else {
                DispatchQueue.main.async { self.state = .idle }
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let cleanupEnabled = AppSettings.cleanupEnabled
                let result: CleanupResult
                if cleanupEnabled {
                    result = await TextCleaner(
                        client: self.ollama, model: AppSettings.ollamaModel
                    ).clean(transcript)
                } else {
                    result = CleanupResult(text: transcript, wasCleaned: false)
                }
                await MainActor.run {
                    self.history.add(result.text)
                    TextInserter.insert(result.text)
                    if cleanupEnabled && !result.wasCleaned {
                        self.onNotice?("Вставлено без ИИ-чистки")
                    }
                    self.state = .idle
                }
            }
        }
    }

    // MARK: - Status for the menu

    func ollamaStatusLine() async -> String {
        guard await ollama.isAvailable() else {
            return "Ollama не запущена — вставляется сырой текст"
        }
        return "Ollama ✓ (\(AppSettings.ollamaModel))"
    }
}
