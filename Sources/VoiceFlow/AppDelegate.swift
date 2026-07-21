import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = DictationCoordinator()
    private var statusItem: StatusItemController?
    private let hotkey = HotkeyListener()
    private let hud = HUDController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(coordinator: coordinator, hotkey: hotkey)

        coordinator.addStateObserver { [weak self] state in
            switch state {
            case .recording: self?.hud.show(.listening)
            case .processing: self?.hud.show(.processing)
            default: self?.hud.hide()
            }
        }
        coordinator.onAudioLevel = { [weak self] level in
            self?.hud.pushLevel(level)
        }
        coordinator.onPreview = { [weak self] text in
            self?.hud.showTranscript(text)
        }

        if !Permissions.accessibilityGranted {
            Permissions.promptAccessibility()
        }
        if !Permissions.microphoneGranted {
            Permissions.requestMicrophone { _ in }
        }

        hotkey.onPress = { [weak self] in self?.coordinator.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.coordinator.hotkeyReleased() }
        hotkey.onTranslatePress = { [weak self] in
            self?.coordinator.hotkeyPressed(translate: true)
        }
        hotkey.onTranslateRelease = { [weak self] in self?.coordinator.hotkeyReleased() }
        hotkey.start()

        coordinator.bootstrap()

        // macOS silently stops delivering events to global monitors after
        // sleep — and occasionally after screen lock or user switching.
        // Re-register on every plausible trigger plus a slow heartbeat.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.coordinator.recoverAfterWake()
            self?.reviveHotkey()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reviveHotkey()
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.reviveHotkey()
        }
        hotkeyHeartbeat = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.reviveHotkey()
        }
    }

    private var hotkeyHeartbeat: Timer?

    /// Re-registering is cheap and idempotent, but start() resets the
    /// pressed-state — never do it mid-recording or the release gets lost.
    private func reviveHotkey() {
        guard coordinator.state != .recording else { return }
        hotkey.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // exit() runs whisper.cpp's static C++ destructors, which abort() in
        // ggml_metal_device_free — every quit left a crash report. Nothing
        // needs graceful teardown here, so flush prefs and leave at once.
        UserDefaults.standard.synchronize()
        _exit(0)
    }
}
