import Foundation

/// Decides whether a recording is worth transcribing at all.
/// Whisper hallucinates on silence, so we gate on duration and level.
public enum AudioGate {
    public static let minDuration: Double = 0.35
    public static let minRMS: Float = 0.004

    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sum / Float(samples.count))
    }

    public static func shouldTranscribe(samples: [Float], sampleRate: Double) -> Bool {
        let duration = Double(samples.count) / sampleRate
        guard duration >= minDuration else { return false }
        return rms(samples) >= minRMS
    }
}
