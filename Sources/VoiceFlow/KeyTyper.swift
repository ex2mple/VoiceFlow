import AppKit

/// Types text into the focused app via synthetic key events. Used by the
/// "живой текст в поле ввода" mode. Requires Accessibility permission.
enum KeyTyper {
    /// Some apps drop long unicode payloads — send small chunks.
    private static let chunkSize = 16

    static func type(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        var units = Array(text.utf16)
        while !units.isEmpty {
            let chunk = Array(units.prefix(chunkSize))
            units.removeFirst(chunk.count)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            up?.post(tap: .cghidEventTap)
        }
    }

    static func backspace(_ count: Int) {
        guard count > 0 else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        let key: CGKeyCode = 51 // delete
        for _ in 0..<count {
            CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)?
                .post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)?
                .post(tap: .cghidEventTap)
        }
    }

    /// Morphs what's already typed into `new`: erases the differing tail,
    /// types the fresh suffix. Returns the number of key events implied —
    /// callers can use it to throttle.
    static func retype(from old: String, to new: String) {
        let oldChars = Array(old)
        let newChars = Array(new)
        var common = 0
        while common < min(oldChars.count, newChars.count),
              oldChars[common] == newChars[common] {
            common += 1
        }
        // Backspace counts key *presses* the target app sees, so count
        // characters (grapheme-ish via Character), not utf16 units.
        backspace(oldChars.count - common)
        if common < newChars.count {
            type(String(newChars[common...]))
        }
    }
}
