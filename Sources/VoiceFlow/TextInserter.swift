import AppKit

/// Puts text into the focused app: clipboard + synthetic ⌘V, then restores
/// what was in the clipboard before. Requires Accessibility permission.
enum TextInserter {
    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)
        postCmdV()

        // Restore the previous clipboard after the paste lands. The dictated
        // text stays recoverable from the history menu.
        if let saved {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                pb.clearContents()
                pb.setString(saved, forType: .string)
            }
        }
    }

    private static func postCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
