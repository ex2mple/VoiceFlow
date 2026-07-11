import AppKit
import VoiceFlowCore

/// The personal dictionary lives in a plain text file the user edits with
/// any editor. Reloaded before every dictation.
enum DictionaryFile {
    static var url: URL {
        ModelLocator.supportDirectory()
            .deletingLastPathComponent()
            .appendingPathComponent("dictionary.txt")
    }

    private static let template = """
    # Персональный словарь VoiceFlow
    # Впиши слова, которые распознаются неправильно: имена, термины, названия.
    # По одному на строку. Строки с # игнорируются.
    #
    # WordStash
    # задеплоить
    """

    static func words() -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return UserDictionary.parse(text)
    }

    static func openInEditor() {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? template.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }
}
