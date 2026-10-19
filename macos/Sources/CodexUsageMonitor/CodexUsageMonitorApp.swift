import AppKit
import Combine
import OSLog

@main
@MainActor
final class CodexUsageMonitorApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static var retainedDelegate: CodexUsageMonitorApp?
    private let store = UsageStore(enabledProviders: Set(MenuBarPreferences.visibleProviders))
    private let statusMenu = NSMenu()
    private let logger = Logger(subsystem: "com.sundaynighttt.codex-usage-monitor", category: "MenuBar")
    private var statusItem: NSStatusItem?
    private var storeCancellable: AnyCancellable?
    private var loginItemError: String?
    private var terminating = false
    private var reviewWindow: UsageReviewWindow?
    private var settingsWindow: ConnectionSettingsWindow?
    private var grokAwaitingWebConfirmation = false
    private var connectionAttempts: [ProviderID: UUID] = [:]

    static func main() {
        if CommandLine.arguments.contains("--check-usage") {
            UsageDiagnostics.run(requestAccess: CommandLine.arguments.contains("--request-access"),
                grokOnly: CommandLine.arguments.contains("--grok-only"))
            return
        }
        let delegate = CodexUsageMonitorApp()
        retainedDelegate = delegate
        let application = NSApplication.shared
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarPreferences.registerDefaults()
        statusMenu.delegate = self
        installStatusItem()
        storeCancellable = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatusTitle() }
        }
        observeSystemEvents()
        if !UserDefaults.standard.bool(forKey: "hasShownConnectionSettings")
            || CommandLine.arguments.contains("--connection-settings") {
            UserDefaults.standard.set(true, forKey: "hasShownConnectionSettings")
            showConnectionSettings()
        }
        if CommandLine.arguments.contains("--review-status") {
            let window = UsageReviewWindow()
            reviewWindow = window
            window.update(states: store.states, now: store.now)
            window.showWindow(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            await store.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        storeCancellable = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ensureStatusItemVisible(reason: "application reopen")
        showConnectionSettings()
        return false
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func installStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = statusMenu
        item.isVisible = true
        statusItem = item
        updateStatusTitle()
        rebuildMenu()
        logger.info("Three-provider status item installed")
    }

    private func observeSystemEvents() {
        NotificationCenter.default.addObserver(self, selector: #selector(restoreStatusItem),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let notifications = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            notifications.addObserver(self, selector: #selector(restoreStatusItem), name: name, object: nil)
        }
    }

    @objc private func restoreStatusItem(_ notification: Notification) {
        ensureStatusItemVisible(reason: notification.name.rawValue)
        if notification.name == NSWorkspace.didWakeNotification { store.refresh() }
    }

    private func ensureStatusItemVisible(reason: String) {
        guard let statusItem, statusItem.button != nil else { installStatusItem(); return }
        statusItem.length = NSStatusItem.variableLength
        statusItem.isVisible = true
        statusItem.menu = statusMenu
        updateStatusTitle()
        logger.info("Status item restored after \(reason, privacy: .public)")
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.image = MenuBarPresentation.image(states: store.states, now: store.now,
            showResetTime: MenuBarPreferences.showResetTime,
            visibleProviders: MenuBarPreferences.visibleProviders)
        let summary = MenuBarPresentation.summary(states: store.states, now: store.now,
            visibleProviders: MenuBarPreferences.visibleProviders)
        button.toolTip = summary + "\n* 이전 성공 값 · 기본 표시는 가장 적게 남은 한도"
        button.setAccessibilityLabel(summary)
        button.setAccessibilityIdentifier("CodexTimeStatusItem")
        reviewWindow?.update(states: store.states, now: store.now)
        settingsWindow?.update(states: store.states, now: store.now,
            canConfirmGrok: grokAwaitingWebConfirmation && store.states[.grok]?.failure == nil
                && store.states[.grok]?.snapshot != nil && store.states[.grok]?.isRefreshing != true)
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()
        statusMenu.addItem(actionItem(title: "계정 연결 및 표시 설정…",
            action: #selector(showConnectionSettings)))
        statusMenu.addItem(.separator())
        addInfoItem("표시할 서비스 · 끄면 자동 조회도 중지", to: statusMenu)
        for id in ProviderID.allCases {
            let item = actionItem(title: id.name, action: #selector(toggleProviderVisibility(_:)))
            item.representedObject = id.rawValue
            item.state = MenuBarPreferences.isVisible(id) ? .on : .off
            item.image = ProviderLogo.image(for: id)
            item.image?.size = NSSize(width: 16, height: 16)
            statusMenu.addItem(item)
        }
        statusMenu.addItem(.separator())
        for id in MenuBarPreferences.visibleProviders {
            let state = store.states[id] ?? ProviderUsageState(id: id)
            let title = "\(id.name) · \(MenuBarPresentation.value(for: state, now: store.now))"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = providerMenu(for: id, state: state)
            statusMenu.addItem(item)
        }
        if MenuBarPreferences.visibleProviders.isEmpty {
            addInfoItem("서비스를 선택하면 사용량이 표시됩니다.", to: statusMenu)
        }
        statusMenu.addItem(.separator())
        let refreshAll = actionItem(title: store.isRefreshing ? "나머지 서비스 새로고침" : "모두 새로고침",
            action: #selector(refreshUsage))
        refreshAll.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        statusMenu.addItem(refreshAll)
        let resetTime = actionItem(title: "메뉴바에 리셋 시간 표시", action: #selector(toggleResetTime))
        resetTime.state = MenuBarPreferences.showResetTime ? .on : .off
        statusMenu.addItem(resetTime)
        let loginItem = actionItem(title: "로그인 시 자동 실행", action: #selector(toggleLaunchAtLogin))
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        statusMenu.addItem(loginItem)
        if let loginItemError { addInfoItem(loginItemError, to: statusMenu) }
        statusMenu.addItem(.separator())
        statusMenu.addItem(actionItem(title: "종료", action: #selector(quitApplication)))
    }

    private func providerMenu(for id: ProviderID, state: ProviderUsageState) -> NSMenu {
        let menu = NSMenu(title: id.name)
        addInfoItem("상태 · \(state.connectionIsPending ? "연결 확인 중" : MenuBarPresentation.status(for: state, now: store.now))", to: menu)
        if id == .grok, grokAwaitingWebConfirmation {
            addInfoItem("웹 대조 대기 · 자동 갱신 꺼짐", to: menu)
        }
        if let snapshot = state.snapshot {
            for window in snapshot.windows {
                let value = window.displayRemainingPercent.map { "\($0)% 남음" } ?? "—"
                addInfoItem("\(window.label) · \(value)", to: menu)
                if let reset = window.resetDate {
                    addInfoItem("리셋 · \(reset.formatted(date: .abbreviated, time: .shortened))", to: menu)
                } else { addInfoItem("리셋 · 미확인", to: menu) }
            }
        } else { addInfoItem("사용량 · —", to: menu) }
        if let lastSuccess = state.lastSuccess {
            addInfoItem("마지막 성공 · \(lastSuccess.formatted(date: .abbreviated, time: .shortened))", to: menu)
        }
        if let error = state.error { addInfoItem("오류 · \(error)", to: menu) }
        menu.addItem(.separator())
        let refresh = actionItem(title: "\(id.name) 새로고침", action: #selector(refreshProvider(_:)))
        refresh.representedObject = id.rawValue
        refresh.isEnabled = !state.isRefreshing
        menu.addItem(refresh)
        let connect = actionItem(title: id == .codex ? "설치·로그인 안내…" : "\(id.name) 연결 설정…",
            action: #selector(showConnectionSettings))
        menu.addItem(connect)
        let help = actionItem(title: id == .grok ? "Grok 웹 사용량 열기" : "공식 안내 열기",
            action: #selector(openProviderHelp(_:)))
        help.representedObject = id.rawValue
        menu.addItem(help)
        return menu
    }

    private func addInfoItem(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func refreshUsage() { store.refresh() }
    @objc private func refreshProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = ProviderID(rawValue: raw) else { return }
        store.refresh(id)
    }
    @objc private func toggleProviderVisibility(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = ProviderID(rawValue: raw) else { return }
        setProviderVisible(id, visible: !MenuBarPreferences.isVisible(id))
    }

    private func setProviderVisible(_ id: ProviderID, visible: Bool) {
        MenuBarPreferences.setVisible(visible, for: id)
        if !visible {
            connectionAttempts[id] = nil
            if id == .grok { grokAwaitingWebConfirmation = false }
        }
        store.setEnabled(visible, for: id)
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func showConnectionSettings() {
        if settingsWindow == nil {
            settingsWindow = ConnectionSettingsWindow(
                onVisibilityChanged: { [weak self] id, visible in self?.setProviderVisible(id, visible: visible) },
                onConnect: { [weak self] id in self?.connectProvider(id) },
                onDisconnect: { [weak self] id in self?.disconnectProvider(id) },
                onOpenHelp: { [weak self] id in self?.openHelp(for: id) },
                onConfirmGrok: { [weak self] in self?.confirmGrokWebMatch() })
        }
        updateStatusTitle()
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func connectProvider(_ id: ProviderID) {
        guard connectionAttempts[id] == nil, store.states[id]?.isRefreshing != true else { return }
        if id == .codex {
            setProviderVisible(id, visible: true)
            store.refresh(id)
            return
        }
        let alert = NSAlert()
        alert.messageText = "\(id.name) 계정 연결"
        if id == .grok {
            alert.informativeText = "이 Mac의 Cursor 로그인 토큰 한 항목만 앱 메모리에서 읽어 공유 사용량과 리셋을 조회합니다. 토큰을 별도 저장하거나 대화·쿠키·갱신 토큰을 읽지 않습니다. 조회 후 본인의 Grok 웹 사용량과 대조해야 자동 갱신이 시작됩니다."
        } else {
            alert.informativeText = "이 Mac의 Claude Code Keychain 항목을 앱 메모리에서 사용해 구독 사용량과 리셋만 조회합니다. OS 권한창이 나타날 수 있습니다. 연결하면 10분마다 갱신하며 토큰을 별도 저장하거나 갱신하지 않습니다."
        }
        alert.addButton(withTitle: "사용량 조회 허용")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let attempt = UUID()
        connectionAttempts[id] = attempt
        if id == .grok {
            grokAwaitingWebConfirmation = false
            UserDefaults.standard.set(false, forKey: "grokCursorUsageVerified")
        } else {
            UserDefaults.standard.set(false, forKey: ClaudeSubscriptionUsageProviderClient.connectionEnabledKey)
        }
        // Enabling refreshes the normal gated client first; join it before the
        // explicit client so each provider retains a single owned request.
        setProviderVisible(id, visible: true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.store.refreshAndWait(id)
            guard self.connectionAttempts[id] == attempt, MenuBarPreferences.isVisible(id) else {
                if self.connectionAttempts[id] == attempt { self.connectionAttempts[id] = nil }
                return
            }
            self.store.connect(id, using: ProductionUsageProviders.interactiveClient(for: id))
            await self.store.refreshAndWait(id)
            guard self.connectionAttempts[id] == attempt else { return }
            self.connectionAttempts[id] = nil
            if id == .claude, self.store.states[id]?.failure == nil, self.store.states[id]?.snapshot != nil {
                UserDefaults.standard.set(true, forKey: ClaudeSubscriptionUsageProviderClient.connectionEnabledKey)
            }
            if id == .grok {
                self.grokAwaitingWebConfirmation = self.store.states[id]?.failure == nil
                    && self.store.states[id]?.snapshot != nil
            }
            self.updateStatusTitle()
            self.rebuildMenu()
        }
    }

    private func confirmGrokWebMatch() {
        guard grokAwaitingWebConfirmation, store.states[.grok]?.failure == nil,
              store.states[.grok]?.snapshot != nil, store.states[.grok]?.isRefreshing != true else { return }
        let alert = NSAlert()
        alert.messageText = "본인의 Grok 웹 사용량과 일치하나요?"
        alert.informativeText = "같은 구독의 사용률과 리셋 시각을 확인한 경우에만 시작하세요. 메뉴바는 원본 잔여율을 내림하므로 웹의 정수 사용률과 1% 차이가 보일 수 있습니다. 계정을 바꾸면 연결을 해제한 뒤 다시 대조하세요."
        alert.addButton(withTitle: "일치함 · 10분 갱신 시작")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.set(true, forKey: "grokCursorUsageVerified")
        grokAwaitingWebConfirmation = false
        store.refresh(.grok)
        updateStatusTitle()
    }

    private func disconnectProvider(_ id: ProviderID) {
        guard id != .codex else { return }
        connectionAttempts[id] = nil
        if id == .grok {
            UserDefaults.standard.set(false, forKey: "grokCursorUsageVerified")
            grokAwaitingWebConfirmation = false
        } else {
            UserDefaults.standard.set(false, forKey: ClaudeSubscriptionUsageProviderClient.connectionEnabledKey)
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.store.disconnect(id)
            self.updateStatusTitle()
        }
    }

    @objc private func openProviderHelp(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = ProviderID(rawValue: raw) else { return }
        openHelp(for: id)
    }

    private func openHelp(for id: ProviderID) {
        let address: String
        switch id {
        case .codex: address = "https://github.com/openai/codex#installation"
        case .grok: address = "https://grok.com/?_s=usage"
        case .claude: address = "https://code.claude.com/docs/en/setup"
        }
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }

    @objc private func toggleResetTime() {
        MenuBarPreferences.showResetTime.toggle()
        updateStatusTitle()
    }
    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItemManager.setEnabled(!LoginItemManager.isEnabled)
            loginItemError = nil
        } catch { loginItemError = "자동 실행 설정을 변경하지 못했습니다." }
    }
    @objc private func quitApplication() { NSApplication.shared.terminate(nil) }
}
