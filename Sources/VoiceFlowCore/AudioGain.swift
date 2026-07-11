import Foundation

/// Auto-gain: quiet microphones produce peaks of 0.05–0.2, which hurts
/// Whisper. Normalize the peak toward a healthy level before transcription.
/// Applied AFTER the silence gate — amplifying room noise would defeat it.
public enum AudioGain {
    public static let targetPeak: Float = 0.9
    public static let maxGain: Float = 25

    public static func normalized(_ samples: [Float]) -> [Float] {
        var peak: Float = 0
        for s in samples { peak = max(peak, abs(s)) }
        guard peak > 0 else { return samples }
        let gain = min(maxGain, targetPeak / peak)
        // Already loud enough — don't touch the signal.
        guard gain > 1.2 else { return samples }
        return samples.map { $0 * gain }
    }
}
