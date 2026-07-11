import Foundation
import VoiceFlowCore

/// Lightweight diagnostics: enabled by `defaults write com.braude.voiceflow debugLog 1`.
/// Appends to ~/Library/Application Support/VoiceFlow/debug.log.
enum DebugLog {
    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: "debugLog")
    }

    private static let url = ModelLocator.supportDirectory()
        .deletingLastPathComponent()
        .appendingPathComponent("debug.log")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        guard enabled else { return }
        let line = "\(formatter.string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(line.utf8).write(to: url)
        }
    }
}
