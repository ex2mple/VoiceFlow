import Foundation

/// Guards against a small LLM "answering" the dictation instead of cleaning it,
/// or wrapping the result in quotes/markdown/thinking tags.
public enum CleanupValidator {
    /// Strips model artifacts: <think> blocks, code fences, surrounding quotes.
    public static func stripArtifacts(_ s: String) -> String {
        var text = s
        text = text.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "^```[a-z]*\\n?|```$", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("\"", "\""), ("«", "»"), ("“", "”")] {
            if text.hasPrefix(open) && text.hasSuffix(close) && text.count > 2 {
                text = String(text.dropFirst(open.count).dropLast(close.count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return text
    }

    /// Returns the cleaned text if it looks like a faithful cleanup of the
    /// original, nil if it is suspicious (then the caller falls back to raw).
    public static func validate(original: String, cleaned: String) -> String? {
        let result = stripArtifacts(cleaned)
        guard !result.isEmpty else { return nil }

        let origLen = Double(original.count)
        let newLen = Double(result.count)
        // Cleanup mostly shortens text; big growth means the model added
        // content of its own. Short phrases get loose bounds (punctuation
        // dominates their length); long ones get a strict floor — a small
        // model that "summarizes" a long dictation loses the author's
        // meaning, and the raw transcript is the better fallback.
        let lower: Double
        switch origLen {
        case ..<30: lower = 0.2
        case ..<120: lower = 0.4
        default: lower = 0.7
        }
        let upper = origLen < 30 ? 3.0 : 1.5
        guard newLen >= origLen * lower, newLen <= origLen * upper else { return nil }

        return result
    }
}
