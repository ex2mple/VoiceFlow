import AppKit
import VoiceFlowCore

/// «Нажмите клавишу…» — плавающая панель, ловящая следующее подходящее
/// нажатие (модификатор или F-клавиша). Главный HotkeyListener на время
/// записи выключается снаружи, чтобы проба клавиш не запускала диктовку.
final class HotkeyRecorderPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var monitor: Any?
    private var completion: ((HotkeySpec?) -> Void)?
    private let hintLabel = NSTextField(labelWithString: "")

    private static let defaultHint = "Модификатор (⌥ ⌘ ⌃ ⇧, Fn) или F-клавиша · Esc — отмена"

    func begin(prompt: String, completion: @escaping (HotkeySpec?) -> Void) {
        finish(nil) // повторный вызов: отменяем прошлую запись
        self.completion = completion

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 110),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        p.title = "VoiceFlow"
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.delegate = self

        let title = NSTextField(labelWithString: prompt)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.alignment = .center
        hintLabel.stringValue = Self.defaultHint
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [title, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        p.contentView?.addSubview(stack)
        if let content = p.contentView {
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                stack.leadingAnchor.constraint(
                    greaterThanOrEqualTo: content.leadingAnchor, constant: 16),
            ])
        }
        panel = p

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            self?.handle(event)
            return nil // пока идёт запись, нажатия никуда дальше не уходят
        }
        NSApp.activate(ignoringOtherApps: true)
        p.center()
        p.makeKeyAndOrderFront(nil)
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if event.keyCode == 53 { // Esc
                finish(nil)
            } else if let name = HotkeySpec.recordableKeys[event.keyCode] {
                finish(.key(code: event.keyCode, name: name))
            } else {
                hintLabel.stringValue =
                    "Эта клавиша печатает текст — нужен модификатор или F-клавиша"
            }
        case .flagsChanged:
            if let m = Hotkey.byKeyCode[event.keyCode] {
                // Реагируем на нажатие, отпускание игнорируем.
                guard m.isPressed(inFlags: event.modifierFlags.rawValue) else { return }
                finish(.modifier(m))
            } else if event.keyCode == 57 {
                hintLabel.stringValue = "Caps Lock не подходит — он залипает"
            }
        default:
            break
        }
    }

    /// Клик по крестику = отмена.
    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }

    private func finish(_ spec: HotkeySpec?) {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        let done = completion
        completion = nil
        if let p = panel {
            p.delegate = nil // без повторного захода через windowWillClose
            p.orderOut(nil)
            panel = nil
        }
        done?(spec)
    }
}
