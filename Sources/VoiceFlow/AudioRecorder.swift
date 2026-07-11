import AVFoundation

/// Records from the default microphone, resampled to 16 kHz mono Float32 —
/// the only format Whisper accepts.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()

    static let sampleRate: Double = 16000

    func start() throws {
        lock.lock()
        samples.removeAll()
        lock.unlock()

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else {
            throw NSError(domain: "VoiceFlow", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Микрофон недоступен"])
        }
        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
            channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw NSError(domain: "VoiceFlow", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Не удалось создать конвертер аудио"])
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = Self.sampleRate / inFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
            var consumed = false
            converter.convert(to: out, error: nil) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard out.frameLength > 0, let data = out.floatChannelData else { return }
            let chunk = Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
            self.lock.lock()
            self.samples.append(contentsOf: chunk)
            self.lock.unlock()
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}
