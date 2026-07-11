import Foundation

/// Cleans raw Whisper output: strips non-speech markers and known
/// hallucinations the model produces on silence/noise (especially in Russian).
public enum TranscriptSanitizer {
    /// Phrases Whisper is known to hallucinate on silent or noisy audio.
    /// Compared case- and punctuation-insensitively against whole segments.
    static let hallucinations: [String] = [
        "субтитры сделал dimatorzok",
        "субтитры создавал dimatorzok",
        "субтитры делал dimatorzok",
        "субтитры сделал диматорзок",
        "субтитры создавал диматорзок",
        "субтитры делал диматорзок",
        "редактор субтитров асемкин",
        "редактор субтитров аслуцкая",
        "корректор аегорова",
        "продолжение следует",
        "спасибо за просмотр",
        "всем спасибо за просмотр",
        "подписывайтесь на канал",
        "ставьте лайки",
        "до новых встреч",
        "игорь негода",
        "thank you for watching",
        "thanks for watching",
        "please subscribe",
        "subtitles by the amaraorg community",
        "sous-titrage société radio-canada",
        "you",
    ]

    public static func clean(_ raw: String) -> String {
        var text = raw

        // Whisper wraps non-speech events in brackets/asterisks/parens:
        // [BLANK_AUDIO], (music), *звонок*, [Music] etc.
        for pattern in ["\\[[^\\]]*\\]", "\\([^)]*\\)", "\\*[^*]*\\*"] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        // Drop segments that are known hallucinations.
        let segments = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var kept: [String] = []
        for segment in segments where !segment.isEmpty {
            if hallucinations.contains(normalize(segment)) { continue }
            kept.append(segment)
        }
        if kept.isEmpty { return "" }

        // Hallucination-only input → nothing; otherwise return the original
        // text minus markers (keeping author punctuation), unless entire
        // segments were dropped — then rebuild from kept segments.
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if kept.count == segments.filter({ !$0.isEmpty }).count {
            return collapseSpaces(cleaned)
        }
        var rebuilt = kept.joined(separator: ". ")
        if !rebuilt.hasSuffix(".") && !rebuilt.hasSuffix("!") && !rebuilt.hasSuffix("?") {
            rebuilt += "."
        }
        return collapseSpaces(rebuilt)
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
    }

    private static func collapseSpaces(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
