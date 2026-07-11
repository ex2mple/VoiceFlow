import Foundation

enum Hotkey: String, CaseIterable {
    case rightOption
    case rightCommand

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: return .option
        case .rightCommand: return .command
        }
    }

    var title: String {
        switch self {
        case .rightOption: return "Правый ⌥ Option"
        case .rightCommand: return "Правый ⌘ Command"
        }
    }
}

import AppKit

enum AppSettings {
    private static let d = UserDefaults.standard

    static var cleanupEnabled: Bool {
        get { d.object(forKey: "cleanupEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "cleanupEnabled") }
    }

    static var hotkey: Hotkey {
        get { Hotkey(rawValue: d.string(forKey: "hotkey") ?? "") ?? .rightOption }
        set { d.set(newValue.rawValue, forKey: "hotkey") }
    }

    static var ollamaModel: String {
        get { d.string(forKey: "ollamaModel") ?? "qwen3:4b-instruct" }
        set { d.set(newValue, forKey: "ollamaModel") }
    }
}
