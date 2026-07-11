import AppKit

/// Hold-to-talk: watches flagsChanged globally for the configured modifier key.
/// Requires Accessibility permission (same one TextInserter needs).
final class HotkeyListener {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onTranslatePress: (() -> Void)?
    var onTranslateRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDown = false
    private var isTranslateDown = false

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handle(e)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handle(e)
            return e
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        isDown = false
        isTranslateDown = false
    }

    private func handle(_ event: NSEvent) {
        let dictate = AppSettings.hotkey
        let translate = AppSettings.translateHotkey
        if event.keyCode == dictate.keyCode {
            let pressed = event.modifierFlags.contains(dictate.flag)
            if pressed && !isDown {
                isDown = true
                onPress?()
            } else if !pressed && isDown {
                isDown = false
                onRelease?()
            }
        } else if event.keyCode == translate.keyCode {
            let pressed = event.modifierFlags.contains(translate.flag)
            if pressed && !isTranslateDown {
                isTranslateDown = true
                onTranslatePress?()
            } else if !pressed && isTranslateDown {
                isTranslateDown = false
                onTranslateRelease?()
            }
        }
    }
}
