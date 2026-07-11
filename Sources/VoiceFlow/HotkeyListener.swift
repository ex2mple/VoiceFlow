import AppKit

/// Hold-to-talk: watches flagsChanged globally for the configured modifier key.
/// Requires Accessibility permission (same one TextInserter needs).
final class HotkeyListener {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDown = false

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
    }

    private func handle(_ event: NSEvent) {
        let hotkey = AppSettings.hotkey
        guard event.keyCode == hotkey.keyCode else { return }
        let pressed = event.modifierFlags.contains(hotkey.flag)
        if pressed && !isDown {
            isDown = true
            onPress?()
        } else if !pressed && isDown {
            isDown = false
            onRelease?()
        }
    }
}
