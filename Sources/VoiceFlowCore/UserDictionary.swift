import Foundation

/// Personal vocabulary: names and terms Whisper tends to mangle.
/// Stored as a plain text file, one word or phrase per line, # for comments.
public enum UserDictionary {
    public static func parse(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Whisper's initial_prompt biases decoding toward the words it contains —
    /// natural-looking text works better than a bare list.
    public static func whisperPrompt(_ words: [String]) -> String? {
        guard !words.isEmpty else { return nil }
        return "Словарь: " + words.joined(separator: ", ") + "."
    }

    /// Extra system-prompt line so the cleanup LLM keeps the exact spelling.
    public static func cleanupHint(_ words: [String]) -> String? {
        guard !words.isEmpty else { return nil }
        return "\nПиши эти слова и имена именно так, не исправляй их: "
            + words.joined(separator: ", ") + "."
    }
}
