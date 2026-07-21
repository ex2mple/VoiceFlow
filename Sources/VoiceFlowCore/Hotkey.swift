import Foundation

/// A single modifier key usable as push-to-talk. Hold-to-talk only works with
/// modifiers: an ordinary key would type into the focused app while held.
public enum Hotkey: String, CaseIterable {
    case rightOption
    case leftOption
    case rightCommand
    case leftCommand
    case rightControl
    case leftControl
    case rightShift
    case leftShift
    case fn

    /// HIToolbox kVK_ virtual key code seen in flagsChanged events.
    public var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .leftOption: return 58
        case .rightCommand: return 54
        case .leftCommand: return 55
        case .rightControl: return 62
        case .leftControl: return 59
        case .rightShift: return 60
        case .leftShift: return 56
        case .fn: return 63
        }
    }

    /// Device-specific NX_DEVICE* bit (IOKit/IOLLEvent.h) present in
    /// NSEvent.modifierFlags.rawValue. The generic flags (.option etc.) can't
    /// tell left from right — releasing right ⌥ while left ⌥ is held would
    /// read as "still pressed" and jam the recording.
    private var flagMask: UInt {
        switch self {
        case .rightOption: return 0x0040
        case .leftOption: return 0x0020
        case .rightCommand: return 0x0010
        case .leftCommand: return 0x0008
        case .rightControl: return 0x2000
        case .leftControl: return 0x0001
        case .rightShift: return 0x0004
        case .leftShift: return 0x0002
        case .fn: return 0x0080_0000  // NX_SECONDARYFNMASK — no left/right variants
        }
    }

    public func isPressed(inFlags rawFlags: UInt) -> Bool {
        rawFlags & flagMask != 0
    }

    public var title: String {
        switch self {
        case .rightOption: return "Правый ⌥ Option"
        case .leftOption: return "Левый ⌥ Option"
        case .rightCommand: return "Правый ⌘ Command"
        case .leftCommand: return "Левый ⌘ Command"
        case .rightControl: return "Правый ⌃ Control"
        case .leftControl: return "Левый ⌃ Control"
        case .rightShift: return "Правый ⇧ Shift"
        case .leftShift: return "Левый ⇧ Shift"
        case .fn: return "Fn / 🌐"
        }
    }

    public static let byKeyCode: [UInt16: Hotkey] =
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.keyCode, $0) })
}

/// What the push-to-talk key actually is: a modifier, or an F-key captured
/// through «Записать клавишу…». Persisted as a string — legacy values are
/// bare Hotkey rawValues, F-keys use "key:<code>:<name>".
public enum HotkeySpec: Equatable {
    case modifier(Hotkey)
    case key(code: UInt16, name: String)

    public var storageValue: String {
        switch self {
        case .modifier(let m): return m.rawValue
        case .key(let code, let name): return "key:\(code):\(name)"
        }
    }

    public init?(storageValue: String) {
        if let m = Hotkey(rawValue: storageValue) {
            self = .modifier(m)
            return
        }
        let parts = storageValue.split(separator: ":", maxSplits: 2,
                                       omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "key",
              let code = UInt16(parts[1]), !parts[2].isEmpty else { return nil }
        self = .key(code: code, name: parts[2])
    }

    public var keyCode: UInt16 {
        switch self {
        case .modifier(let m): return m.keyCode
        case .key(let code, _): return code
        }
    }

    public var title: String {
        switch self {
        case .modifier(let m): return m.title
        case .key(_, let name): return name
        }
    }

    /// Keys allowed besides modifiers. F-keys only: the event tap swallows
    /// the configured key system-wide, so a character key would become
    /// untypeable everywhere.
    public static let recordableKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",
    ]
}
