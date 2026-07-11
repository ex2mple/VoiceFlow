import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = DictationCoordinator()
    private var statusItem: StatusItemController?
    private let hotkey = HotkeyListener()
    private let hud = HUDController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(coordinator: coordinator)

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

        if !Permissions.accessibilityGranted {
            Permissions.promptAccessibility()
        }
        if !Permissions.microphoneGranted {
            Permissions.requestMicrophone { _ in }
        }

        hotkey.onPress = { [weak self] in self?.coordinator.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.coordinator.hotkeyReleased() }
        hotkey.start()

        coordinator.bootstrap()
    }
}
