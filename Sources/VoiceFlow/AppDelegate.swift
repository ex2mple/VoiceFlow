import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = DictationCoordinator()
    private var statusItem: StatusItemController?
    private let hotkey = HotkeyListener()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(coordinator: coordinator)

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
