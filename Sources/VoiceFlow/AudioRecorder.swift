import AVFoundation
import VoiceFlowCore

/// Records from the default microphone, resampled to 16 kHz mono Float32 —
/// the only format Whisper accepts.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()

    /// Called on the main queue with the RMS of each captured chunk.
    var onLevel: ((Float) -> Void)?

    static let sampleRate: Double = 16000

    func start() throws {
        lock.lock()
        samples.removeAll()
        lock.unlock()

        let input = engine.inputNode
        // Route to the user-chosen microphone (nil = system default).
        if let uid = AppSettings.inputDeviceUID,
           let device = AudioDevices.inputs().first(where: { $0.uid == uid }),
           let audioUnit = input.audioUnit {
            var deviceID = device.id
            AudioUnitSetProperty(
                audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0,
                &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
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
            if let onLevel = self.onLevel {
                let rms = AudioGate.rms(chunk)
                DispatchQueue.main.async { onLevel(rms) }
            }
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

    /// Copy of everything captured so far — feeds the live preview while
    /// recording continues.
    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}
