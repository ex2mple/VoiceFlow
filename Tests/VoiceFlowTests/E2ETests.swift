import Foundation
import VoiceFlowCore

/// Opt-in end-to-end check: real Whisper model + (if running) real Ollama.
/// Enable with VOICEFLOW_E2E=1; audio file path in VOICEFLOW_E2E_WAV
/// (16 kHz mono 16-bit WAV, e.g. produced by `say` + `afconvert`).
func runE2ETestsIfRequested() {
    guard ProcessInfo.processInfo.environment["VOICEFLOW_E2E"] == "1" else { return }
    guard ModelLocator.modelExists else {
        print("• e2e: SKIPPED — модель не скачана (make model)")
        return
    }
    guard let wavPath = ProcessInfo.processInfo.environment["VOICEFLOW_E2E_WAV"],
          let samples = try? WAV.loadMono16kFloat(path: wavPath) else {
        print("• e2e: SKIPPED — нет VOICEFLOW_E2E_WAV")
        return
    }

    var transcript = ""
    T.run("e2e: whisper transcribes synthesized russian speech") {
        let engine = try WhisperEngine(modelPath: ModelLocator.modelPath().path)
        let started = Date()
        transcript = TranscriptSanitizer.clean(engine.transcribe(samples))
        let elapsed = Date().timeIntervalSince(started)
        print("  → «\(transcript)» за \(String(format: "%.2f", elapsed))с")
        let lower = transcript.lowercased()
        T.expect(lower.contains("суббот"), "ожидали слово «субботу» в: \(transcript)")
        T.expect(lower.contains("запиши"), "ожидали слово «запиши» в: \(transcript)")
    }

    T.run("e2e: ollama cleanup (если запущена)") {
        let semaphore = DispatchSemaphore(value: 0)
        var result: CleanupResult?
        var available = false
        Task {
            let client = OllamaClient()
            available = await client.isAvailable()
            if available {
                result = await TextCleaner(client: client, model: "qwen3:4b-instruct").clean(transcript)
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard available else {
            print("  → SKIPPED: Ollama не запущена")
            return
        }
        guard let result else {
            T.expect(false, "cleanup не вернул результат")
            return
        }
        print("  → cleaned=\(result.wasCleaned): «\(result.text)»")
        T.expect(result.wasCleaned, "чистка должна была сработать")
        let lower = result.text.lowercased()
        T.expect(!lower.contains("короче") && !lower.contains(" ну "),
                 "слова-паразиты должны исчезнуть: \(result.text)")
        T.expect(lower.contains("суббот"), "смысл (суббота) должен сохраниться: \(result.text)")
    }
}

/// Minimal WAV reader for the test fixture (PCM 16-bit little-endian).
enum WAV {
    static func loadMono16kFloat(path: String) throws -> [Float] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        // Find the "data" chunk instead of assuming a 44-byte header.
        guard let range = data.range(of: Data("data".utf8)) else {
            throw NSError(domain: "WAV", code: 1)
        }
        let start = range.upperBound + 4 // skip chunk size
        let pcm = data[start...]
        var samples = [Float]()
        samples.reserveCapacity(pcm.count / 2)
        var i = pcm.startIndex
        while i + 1 < pcm.endIndex {
            let lo = UInt16(pcm[i]), hi = UInt16(pcm[i + 1])
            let value = Int16(bitPattern: lo | (hi << 8))
            samples.append(Float(value) / 32768.0)
            i += 2
        }
        return samples
    }
}
