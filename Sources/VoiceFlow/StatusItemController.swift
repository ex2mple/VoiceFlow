import AppKit
import ServiceManagement

final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let coordinator: DictationCoordinator
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "Запуск…", action: nil, keyEquivalent: "")
    private let ollamaLine = NSMenuItem(title: "Ollama: проверка…", action: nil, keyEquivalent: "")
    private var noticeResetTimer: Timer?

    init(coordinator: DictationCoordinator) {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.coordinator = coordinator
        super.init()

        buildMenu()
        item.menu = menu
        render(state: .loadingModel)

        coordinator.addStateObserver { [weak self] state in
            self?.render(state: state)
        }
        coordinator.onNotice = { [weak self] text in
            self?.flash(text)
        }
    }

    // MARK: - Icon states

    private func render(state: DictationCoordinator.State) {
        guard let button = item.button else { return }
        noticeResetTimer?.invalidate()
        button.title = ""
        switch state {
        case .loadingModel:
            button.image = symbol("hourglass")
            statusLine.title = "Загружается модель…"
        case .downloadingModel(let percent):
            button.image = symbol("arrow.down.circle")
            button.title = " \(percent)%"
            statusLine.title = "Скачивается модель Whisper (\(percent)%)"
        case .idle:
            button.image = symbol("mic")
            statusLine.title = "Готов: зажми \(AppSettings.hotkey.title) и говори"
        case .recording:
            button.image = symbol("record.circle.fill")
            statusLine.title = "Запись…"
        case .processing:
            button.image = symbol("waveform")
            statusLine.title = "Распознаю…"
        case .failed(let message):
            button.image = symbol("exclamationmark.triangle")
            statusLine.title = "Ошибка: \(message)"
        }
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "VoiceFlow")
        image?.isTemplate = true
        return image
    }

    private func flash(_ text: String) {
        guard let button = item.button else { return }
        button.title = " \(text)"
        noticeResetTimer?.invalidate()
        noticeResetTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.render(state: self.coordinator.state)
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.delegate = self
        statusLine.isEnabled = false
        ollamaLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(ollamaLine)
        menu.addItem(.separator())

        let cleanup = NSMenuItem(
            title: "ИИ-чистка текста", action: #selector(toggleCleanup), keyEquivalent: "")
        cleanup.target = self
        cleanup.tag = MenuTag.cleanup.rawValue
        menu.addItem(cleanup)

        let hotkeyMenu = NSMenu()
        for hk in Hotkey.allCases {
            let i = NSMenuItem(title: hk.title, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = hk.rawValue
            hotkeyMenu.addItem(i)
        }
        let hotkeyRoot = NSMenuItem(title: "Клавиша диктовки", action: nil, keyEquivalent: "")
        hotkeyRoot.submenu = hotkeyMenu
        menu.addItem(hotkeyRoot)

        let sensTitle = NSMenuItem(title: "Чувствительность волны", action: nil, keyEquivalent: "")
        sensTitle.isEnabled = false
        menu.addItem(sensTitle)
        let sliderItem = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        let slider = NSSlider(
            value: AppSettings.waveSensitivity, minValue: 0.4, maxValue: 2.5,
            target: self, action: #selector(sensitivityChanged(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 20, y: 3, width: 180, height: 20)
        container.addSubview(slider)
        sliderItem.view = container
        menu.addItem(sliderItem)

        let historyRoot = NSMenuItem(title: "История", action: nil, keyEquivalent: "")
        historyRoot.submenu = NSMenu()
        historyRoot.tag = MenuTag.history.rawValue
        menu.addItem(historyRoot)
        menu.addItem(.separator())

        let login = NSMenuItem(
            title: "Запускать при входе", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.tag = MenuTag.login.rawValue
        menu.addItem(login)

        let ax = NSMenuItem(
            title: "Выдать доступ Accessibility…", action: #selector(openAccessibility),
            keyEquivalent: "")
        ax.target = self
        ax.tag = MenuTag.accessibility.rawValue
        menu.addItem(ax)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    private enum MenuTag: Int {
        case cleanup = 1, history, login, accessibility
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: MenuTag.cleanup.rawValue)?.state =
            AppSettings.cleanupEnabled ? .on : .off
        menu.item(withTag: MenuTag.login.rawValue)?.state =
            SMAppService.mainApp.status == .enabled ? .on : .off
        menu.item(withTag: MenuTag.accessibility.rawValue)?.isHidden =
            Permissions.accessibilityGranted

        if let hotkeyMenu = menu.items.first(where: { $0.submenu != nil && $0.tag == 0 && $0.title == "Клавиша диктовки" })?.submenu {
            for i in hotkeyMenu.items {
                i.state = (i.representedObject as? String) == AppSettings.hotkey.rawValue ? .on : .off
            }
        }

        if let historyMenu = menu.item(withTag: MenuTag.history.rawValue)?.submenu {
            historyMenu.removeAllItems()
            if coordinator.history.entries.isEmpty {
                let empty = NSMenuItem(title: "Пока пусто", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                historyMenu.addItem(empty)
            }
            for entry in coordinator.history.entries {
                let title = entry.text.count > 60
                    ? String(entry.text.prefix(60)) + "…" : entry.text
                let i = NSMenuItem(title: title, action: #selector(copyHistory(_:)),
                                   keyEquivalent: "")
                i.target = self
                i.representedObject = entry.text
                historyMenu.addItem(i)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            let line = await self.coordinator.ollamaStatusLine()
            await MainActor.run { self.ollamaLine.title = line }
        }
    }

    // MARK: - Actions

    @objc private func toggleCleanup() {
        AppSettings.cleanupEnabled.toggle()
    }

    @objc private func sensitivityChanged(_ sender: NSSlider) {
        AppSettings.waveSensitivity = sender.doubleValue
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let hk = Hotkey(rawValue: raw) else { return }
        AppSettings.hotkey = hk
        render(state: coordinator.state)
    }

    @objc private func copyHistory(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash("Скопировано")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            flash("Не получилось: \(error.localizedDescription)")
        }
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }
}
