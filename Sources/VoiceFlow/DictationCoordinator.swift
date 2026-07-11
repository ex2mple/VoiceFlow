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
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((State) -> Void)?
    /// Short message worth flashing near the menu bar icon ("вставлено без чистки" etc).
    var onNotice: ((String) -> Void)?

    let history = HistoryStore()
    private let recorder = AudioRecorder()
    private let ollama = OllamaClient()
    private var whisper: WhisperEngine?
    private let whisperQueue = DispatchQueue(label: "voiceflow.whisper")

    // MARK: - Startup

    func bootstrap() {
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
        } catch {
            onNotice?(error.localizedDescription)
        }
    }

    func hotkeyReleased() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        guard AudioGate.shouldTranscribe(samples: samples, sampleRate: AudioRecorder.sampleRate) else {
            state = .idle
            return
        }
        state = .processing
        process(samples)
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
