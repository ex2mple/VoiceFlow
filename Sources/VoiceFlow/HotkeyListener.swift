import AppKit
import VoiceFlowCore

/// Hold-to-talk. Modifier hotkeys are watched via flagsChanged monitors;
/// F-key hotkeys via a CGEventTap that swallows the key so it doesn't reach
/// the focused app. Requires Accessibility permission (same one TextInserter
/// needs).
final class HotkeyListener {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onTranslatePress: (() -> Void)?
    var onTranslateRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var isDown = false
    private var isTranslateDown = false

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e)
            return e
        }
        startTapIfNeeded()
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        tapSource = nil
        isDown = false
        isTranslateDown = false
    }

    // MARK: - Modifier keys (flagsChanged monitors)

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.rawValue
        if case .modifier(let m) = AppSettings.hotkey, event.keyCode == m.keyCode {
            transition(pressed: m.isPressed(inFlags: flags), state: &isDown,
                       label: "dictate", press: onPress, release: onRelease)
        } else if case .modifier(let m) = AppSettings.translateHotkey,
                  event.keyCode == m.keyCode {
            transition(pressed: m.isPressed(inFlags: flags), state: &isTranslateDown,
                       label: "translate", press: onTranslatePress, release: onTranslateRelease)
        }
    }

    private func transition(pressed: Bool, state: inout Bool, label: String,
                            press: (() -> Void)?, release: (() -> Void)?) {
        if pressed && !state {
            state = true
            DebugLog.log("hotkey: \(label) down")
            press?()
        } else if !pressed && state {
            state = false
            DebugLog.log("hotkey: \(label) up")
            release?()
        }
    }

    // MARK: - F-keys (event tap; consumes the configured key)

    private func startTapIfNeeded() {
        let wantsTap = [AppSettings.hotkey, AppSettings.translateHotkey].contains {
            if case .key = $0 { return true }
            return false
        }
        guard wantsTap else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon).takeUnretainedValue()
            return listener.handleTap(type: type, event: event)
        }
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap = eventTap else {
            DebugLog.log("hotkey: event tap creation failed (нет Accessibility?)")
            return
        }
        tapSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS pauses slow taps; unlike the NSEvent monitors, it tells us —
        // re-enable and keep living.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            DebugLog.log("hotkey: tap re-enabled")
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if case .key(let c, _) = AppSettings.hotkey, c == code {
            return consume(type: type, event: event, state: &isDown,
                           label: "dictate", press: onPress, release: onRelease)
        }
        if case .key(let c, _) = AppSettings.translateHotkey, c == code {
            return consume(type: type, event: event, state: &isTranslateDown,
                           label: "translate", press: onTranslatePress,
                           release: onTranslateRelease)
        }
        return Unmanaged.passUnretained(event)
    }

    private func consume(type: CGEventType, event: CGEvent, state: inout Bool,
                         label: String, press: (() -> Void)?,
                         release: (() -> Void)?) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            // ⌘F5 и прочие сочетания оставляем приложениям.
            let shortcutFlags: CGEventFlags = [
                .maskCommand, .maskAlternate, .maskControl, .maskShift,
            ]
            if !state && !event.flags.intersection(shortcutFlags).isEmpty {
                return Unmanaged.passUnretained(event)
            }
            if !state {
                state = true
                DebugLog.log("hotkey: \(label) down (tap)")
                // Не задерживаем доставку событий работой в колбэке —
                // медленный tap macOS отключает.
                DispatchQueue.main.async { press?() }
            }
            return nil // сам хоткей и его автоповтор в приложения не попадают
        case .keyUp:
            guard state else { return Unmanaged.passUnretained(event) }
            state = false
            DebugLog.log("hotkey: \(label) up (tap)")
            DispatchQueue.main.async { release?() }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
