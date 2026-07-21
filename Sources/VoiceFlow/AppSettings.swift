import Foundation
import VoiceFlowCore

enum AppSettings {
    private static let d = UserDefaults.standard

    static var cleanupEnabled: Bool {
        get { d.object(forKey: "cleanupEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "cleanupEnabled") }
    }

    static var hotkey: HotkeySpec {
        get { HotkeySpec(storageValue: d.string(forKey: "hotkey") ?? "") ?? .modifier(.rightOption) }
        set { d.set(newValue.storageValue, forKey: "hotkey") }
    }

    /// Own setting since the keys became configurable; the fallback keeps the
    /// old behaviour «перевод на другой из двух клавиш» for existing users.
    static var translateHotkey: HotkeySpec {
        get {
            if let hk = HotkeySpec(storageValue: d.string(forKey: "translateHotkey") ?? "") {
                return hk
            }
            return hotkey == .modifier(.rightOption)
                ? .modifier(.rightCommand) : .modifier(.rightOption)
        }
        set { d.set(newValue.storageValue, forKey: "translateHotkey") }
    }

    /// Скорость печати пользователя (слов/мин) — база для «сэкономлено».
    static var typingWPM: Double {
        get {
            let v = d.double(forKey: "typingWPM")
            return v > 0 ? v : 40
        }
        set { d.set(min(300, max(5, newValue)), forKey: "typingWPM") }
    }

    static var soundsEnabled: Bool {
        get { d.object(forKey: "soundsEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "soundsEnabled") }
    }

    /// nil = системный микрофон по умолчанию.
    static var inputDeviceUID: String? {
        get { d.string(forKey: "inputDeviceUID") }
        set { d.set(newValue, forKey: "inputDeviceUID") }
    }

    static var ollamaModel: String {
        get { d.string(forKey: "ollamaModel") ?? "qwen3:4b-instruct" }
        set { d.set(newValue, forKey: "ollamaModel") }
    }

    /// Where the live partial transcript goes while dictating.
    enum LiveTextTarget: String, CaseIterable {
        case hud      // в капсуле над волной
        case cursor   // печатается сразу в активное поле

        var title: String {
            switch self {
            case .hud: return "В капсуле"
            case .cursor: return "Сразу в поле ввода"
            }
        }
    }

    static var liveTextTarget: LiveTextTarget {
        get { LiveTextTarget(rawValue: d.string(forKey: "liveTextTarget") ?? "") ?? .hud }
        set { d.set(newValue.rawValue, forKey: "liveTextTarget") }
    }

    /// Multiplier for the HUD waveform (0.4 quiet room … 2.5 loud gain).
    static var waveSensitivity: Double {
        get { d.object(forKey: "waveSensitivity") as? Double ?? 1.0 }
        set { d.set(newValue, forKey: "waveSensitivity") }
    }
}
