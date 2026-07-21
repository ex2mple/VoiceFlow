import AppKit
import ServiceManagement
import VoiceFlowCore

final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let coordinator: DictationCoordinator
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "Запуск…", action: nil, keyEquivalent: "")
    private let sensValueLabel = NSTextField(labelWithString: "")
    private let ollamaLine = NSMenuItem(title: "Ollama: проверка…", action: nil, keyEquivalent: "")
    private let ollamaInstallItem = NSMenuItem(
        title: "Включить ИИ-чистку: скачать Ollama…", action: nil, keyEquivalent: "")
    private var noticeResetTimer: Timer?

    private let hotkeyListener: HotkeyListener
    private let keyRecorder = HotkeyRecorderPanel()

    init(coordinator: DictationCoordinator, hotkey: HotkeyListener) {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.coordinator = coordinator
        self.hotkeyListener = hotkey
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
            statusLine.title = "Диктовка: \(AppSettings.hotkey.title) · Перевод EN: \(AppSettings.translateHotkey.title)"
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
        ollamaInstallItem.action = #selector(openOllamaDownload)
        ollamaInstallItem.target = self
        ollamaInstallItem.isHidden = true
        menu.addItem(ollamaInstallItem)
        menu.addItem(.separator())

        let cleanup = NSMenuItem(
            title: "ИИ-чистка текста", action: #selector(toggleCleanup), keyEquivalent: "")
        cleanup.target = self
        cleanup.tag = MenuTag.cleanup.rawValue
        menu.addItem(cleanup)

        menu.addItem(hotkeySubmenu(title: "Клавиша диктовки", tag: .hotkey))
        menu.addItem(hotkeySubmenu(title: "Клавиша перевода EN", tag: .translateHotkey))

        let micRoot = NSMenuItem(title: "Микрофон", action: nil, keyEquivalent: "")
        micRoot.submenu = NSMenu()
        micRoot.tag = MenuTag.microphone.rawValue
        menu.addItem(micRoot)

        let fixMic = NSMenuItem(
            title: "Починить микрофон", action: #selector(fixMicrophone), keyEquivalent: "")
        fixMic.target = self
        menu.addItem(fixMic)

        let sounds = NSMenuItem(
            title: "Звуки записи", action: #selector(toggleSounds), keyEquivalent: "")
        sounds.target = self
        sounds.tag = MenuTag.sounds.rawValue
        menu.addItem(sounds)

        let liveTextMenu = NSMenu()
        for target in AppSettings.LiveTextTarget.allCases {
            let i = NSMenuItem(title: target.title, action: #selector(selectLiveText(_:)),
                               keyEquivalent: "")
            i.target = self
            i.representedObject = target.rawValue
            liveTextMenu.addItem(i)
        }
        let liveTextRoot = NSMenuItem(title: "Живой текст", action: nil, keyEquivalent: "")
        liveTextRoot.submenu = liveTextMenu
        liveTextRoot.tag = MenuTag.liveText.rawValue
        menu.addItem(liveTextRoot)

        let sensTitle = NSMenuItem(title: "Чувствительность волны", action: nil, keyEquivalent: "")
        sensTitle.isEnabled = false
        menu.addItem(sensTitle)
        let sliderItem = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        let slider = NSSlider(
            value: AppSettings.waveSensitivity, minValue: 0.4, maxValue: 2.5,
            target: self, action: #selector(sensitivityChanged(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 20, y: 3, width: 145, height: 20)
        container.addSubview(slider)
        sensValueLabel.frame = NSRect(x: 168, y: 5, width: 44, height: 16)
        sensValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        sensValueLabel.textColor = .secondaryLabelColor
        sensValueLabel.stringValue = Self.sensitivityText(AppSettings.waveSensitivity)
        container.addSubview(sensValueLabel)
        sliderItem.view = container
        menu.addItem(sliderItem)

        let historyRoot = NSMenuItem(title: "История", action: nil, keyEquivalent: "")
        historyRoot.submenu = NSMenu()
        historyRoot.tag = MenuTag.history.rawValue
        menu.addItem(historyRoot)

        let statsItem = NSMenuItem(
            title: "Статистика…", action: #selector(openStats), keyEquivalent: "")
        statsItem.target = self
        menu.addItem(statsItem)

        let dictItem = NSMenuItem(
            title: "Словарь…", action: #selector(openDictionary), keyEquivalent: "")
        dictItem.target = self
        menu.addItem(dictItem)
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
        case cleanup = 1, history, login, accessibility, liveText, microphone, sounds,
             hotkey, translateHotkey
    }

    private func hotkeySubmenu(title: String, tag: MenuTag) -> NSMenuItem {
        // Наполняется в menuNeedsUpdate — записанная F-клавиша появляется
        // отдельной строкой с галочкой.
        let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        root.submenu = NSMenu()
        root.tag = tag.rawValue
        return root
    }

    private func populateHotkeyMenu(tag: MenuTag, current: HotkeySpec,
                                    select: Selector, record: Selector) {
        guard let submenu = menu.item(withTag: tag.rawValue)?.submenu else { return }
        submenu.removeAllItems()
        if case .key = current {
            let i = NSMenuItem(title: current.title, action: select, keyEquivalent: "")
            i.target = self
            i.representedObject = current.storageValue
            i.state = .on
            submenu.addItem(i)
            submenu.addItem(.separator())
        }
        for hk in Hotkey.allCases {
            let spec = HotkeySpec.modifier(hk)
            let i = NSMenuItem(title: hk.title, action: select, keyEquivalent: "")
            i.target = self
            i.representedObject = spec.storageValue
            i.state = spec == current ? .on : .off
            submenu.addItem(i)
        }
        submenu.addItem(.separator())
        let rec = NSMenuItem(title: "Записать клавишу…", action: record, keyEquivalent: "")
        rec.target = self
        submenu.addItem(rec)
    }

    private let statsWindow = StatsWindowController()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: MenuTag.cleanup.rawValue)?.state =
            AppSettings.cleanupEnabled ? .on : .off
        menu.item(withTag: MenuTag.sounds.rawValue)?.state =
            AppSettings.soundsEnabled ? .on : .off

        if let micMenu = menu.item(withTag: MenuTag.microphone.rawValue)?.submenu {
            micMenu.removeAllItems()
            let system = NSMenuItem(
                title: "Системный по умолчанию", action: #selector(selectMicrophone(_:)),
                keyEquivalent: "")
            system.target = self
            system.state = AppSettings.inputDeviceUID == nil ? .on : .off
            micMenu.addItem(system)
            for device in AudioDevices.inputs() {
                let i = NSMenuItem(
                    title: device.name, action: #selector(selectMicrophone(_:)),
                    keyEquivalent: "")
                i.target = self
                i.representedObject = device.uid
                i.state = AppSettings.inputDeviceUID == device.uid ? .on : .off
                micMenu.addItem(i)
            }
        }
        menu.item(withTag: MenuTag.login.rawValue)?.state =
            SMAppService.mainApp.status == .enabled ? .on : .off
        menu.item(withTag: MenuTag.accessibility.rawValue)?.isHidden =
            Permissions.accessibilityGranted

        if let liveTextMenu = menu.item(withTag: MenuTag.liveText.rawValue)?.submenu {
            for i in liveTextMenu.items {
                i.state = (i.representedObject as? String)
                    == AppSettings.liveTextTarget.rawValue ? .on : .off
            }
        }

        populateHotkeyMenu(tag: .hotkey, current: AppSettings.hotkey,
                           select: #selector(selectHotkey(_:)),
                           record: #selector(recordDictationHotkey))
        populateHotkeyMenu(tag: .translateHotkey, current: AppSettings.translateHotkey,
                           select: #selector(selectTranslateHotkey(_:)),
                           record: #selector(recordTranslateHotkey))

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
            let status = await self.coordinator.aiStatus()
            await MainActor.run {
                self.ollamaLine.title = status.line
                self.ollamaInstallItem.isHidden = !status.ollamaMissing
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleCleanup() {
        AppSettings.cleanupEnabled.toggle()
    }

    @objc private func openOllamaDownload() {
        NSWorkspace.shared.open(URL(string: "https://ollama.com/download/mac")!)
    }

    @objc private func toggleSounds() {
        AppSettings.soundsEnabled.toggle()
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        AppSettings.inputDeviceUID = sender.representedObject as? String
    }

    /// Manual escape hatch for the system-wide mic wedge — same volume-rewrite
    /// trick the app applies automatically when a recording comes back dead.
    @objc private func fixMicrophone() {
        let kicked = AudioDevices.kickInput(uid: AppSettings.inputDeviceUID)
        flash(kicked ? "Микрофон перезапущен" : "Не удалось — подёргайте слайдер входа")
    }

    @objc private func openStats() {
        statsWindow.show(stats: coordinator.stats)
    }

    @objc private func openDictionary() {
        DictionaryFile.openInEditor()
    }

    @objc private func selectLiveText(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let target = AppSettings.LiveTextTarget(rawValue: raw) else { return }
        AppSettings.liveTextTarget = target
    }

    @objc private func sensitivityChanged(_ sender: NSSlider) {
        AppSettings.waveSensitivity = sender.doubleValue
        sensValueLabel.stringValue = Self.sensitivityText(sender.doubleValue)
    }

    private static func sensitivityText(_ value: Double) -> String {
        String(format: "×%.1f", value)
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let spec = HotkeySpec(storageValue: raw) else { return }
        applyHotkeys(dictate: spec, translate: nil)
    }

    @objc private func selectTranslateHotkey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let spec = HotkeySpec(storageValue: raw) else { return }
        applyHotkeys(dictate: nil, translate: spec)
    }

    @objc private func recordDictationHotkey() {
        captureHotkey(prompt: "Нажмите клавишу для диктовки") { [weak self] spec in
            self?.applyHotkeys(dictate: spec, translate: nil)
        }
    }

    @objc private func recordTranslateHotkey() {
        captureHotkey(prompt: "Нажмите клавишу для перевода") { [weak self] spec in
            self?.applyHotkeys(dictate: nil, translate: spec)
        }
    }

    private func captureHotkey(prompt: String, apply: @escaping (HotkeySpec) -> Void) {
        // Пока идёт запись, боевой слушатель молчит — иначе проба клавиши
        // тут же запустила бы диктовку.
        hotkeyListener.stop()
        keyRecorder.begin(prompt: prompt) { [weak self] spec in
            if let spec {
                apply(spec) // applyHotkeys перезапустит слушатель
            } else {
                self?.hotkeyListener.start()
            }
        }
    }

    private func applyHotkeys(dictate: HotkeySpec?, translate: HotkeySpec?) {
        if let dictate {
            if dictate == AppSettings.translateHotkey, dictate != AppSettings.hotkey {
                AppSettings.translateHotkey = AppSettings.hotkey
                flash("Клавиши поменялись местами")
            }
            AppSettings.hotkey = dictate
        }
        if let translate {
            if translate == AppSettings.hotkey, translate != AppSettings.translateHotkey {
                AppSettings.hotkey = AppSettings.translateHotkey
                flash("Клавиши поменялись местами")
            }
            AppSettings.translateHotkey = translate
        }
        // Перезапуск: слушателю может понадобиться (или больше не нужен)
        // event tap для F-клавиш.
        hotkeyListener.start()
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
