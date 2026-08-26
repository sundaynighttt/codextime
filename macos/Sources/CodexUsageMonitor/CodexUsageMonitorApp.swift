import AppKit
import Combine
import OSLog

@main
@MainActor
final class CodexUsageMonitorApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static var retainedDelegate: CodexUsageMonitorApp?

    private let store = UsageStore()
    private let statusMenu = NSMenu()
    private let logger = Logger(
        subsystem: "com.sundaynighttt.codex-usage-monitor",
        category: "MenuBar"
    )
    private var statusItem: NSStatusItem?
    private var storeCancellable: AnyCancellable?
    private var loginItemError: String?

    static func main() {
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
        observeUsageChanges()
        observeSystemEvents()
    }

    func applicationWillTerminate(_ notification: Notification) {
        storeCancellable = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        ensureStatusItemVisible(reason: "application reopen")
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.performClick(nil)
        }
        return false
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func installStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = statusMenu
        item.isVisible = true
        statusItem = item
        updateStatusTitle()
        rebuildMenu()
        logger.info(
            "Status item installed; visible=\(item.isVisible); resetTime=\(MenuBarPreferences.showResetTime)"
        )
    }

    private func observeUsageChanges() {
        storeCancellable = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusTitle()
            }
        }
    }

    private func observeSystemEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restoreStatusItem),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self,
            selector: #selector(restoreStatusItem),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(restoreStatusItem),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func restoreStatusItem(_ notification: Notification) {
        ensureStatusItemVisible(reason: notification.name.rawValue)
    }

    private func ensureStatusItemVisible(reason: String) {
        guard let statusItem, statusItem.button != nil else {
            installStatusItem()
            return
        }

        statusItem.length = NSStatusItem.variableLength
        statusItem.isVisible = true
        statusItem.menu = statusMenu
        updateStatusTitle()
        logger.info(
            "Status item restored after \(reason, privacy: .public); visible=\(statusItem.isVisible); resetTime=\(MenuBarPreferences.showResetTime)"
        )
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }

        let title = store.menuTitle(showResetTime: MenuBarPreferences.showResetTime)
        button.title = title
        button.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        button.toolTip = "Codex 남은 사용량"
        button.setAccessibilityLabel("Codex 남은 사용량 \(title)")
        button.setAccessibilityIdentifier("CodexTimeStatusItem")
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()

        if let buckets = store.report?.buckets {
            for (index, bucket) in buckets.enumerated() {
                if index > 0 {
                    statusMenu.addItem(.separator())
                }
                addSectionHeader(bucket.name)
                addInfoItem(UsageFormatter.detail(for: bucket, now: store.now))
                if let secondary = bucket.secondary {
                    let resetDate = secondary.resetsAt.map {
                        Date(timeIntervalSince1970: TimeInterval($0))
                    }
                    addInfoItem(
                        "추가 한도 \(max(0, 100 - secondary.usedPercent))% · "
                            + UsageFormatter.remainingTime(until: resetDate, now: store.now)
                    )
                }
            }
        } else if store.isRefreshing {
            addInfoItem("Codex 사용량 확인 중…")
        }

        if let error = store.errorMessage {
            addInfoItem(error)
        }
        if let loginItemError {
            addInfoItem(loginItemError)
        }

        statusMenu.addItem(.separator())

        let refreshItem = actionItem(
            title: store.isRefreshing ? "새로고침 중…" : "지금 새로고침",
            action: #selector(refreshUsage)
        )
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        refreshItem.isEnabled = !store.isRefreshing
        statusMenu.addItem(refreshItem)

        let resetTimeItem = actionItem(
            title: "메뉴바에 리셋 시간 표시",
            action: #selector(toggleResetTime)
        )
        resetTimeItem.state = MenuBarPreferences.showResetTime ? .on : .off
        statusMenu.addItem(resetTimeItem)

        let loginItem = actionItem(
            title: "로그인 시 자동 실행",
            action: #selector(toggleLaunchAtLogin)
        )
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        statusMenu.addItem(loginItem)

        statusMenu.addItem(actionItem(
            title: "Codex 사용량 설정 열기",
            action: #selector(openUsageSettings)
        ))

        if let lastUpdated = store.lastUpdated {
            addInfoItem("업데이트 \(lastUpdated.formatted(date: .omitted, time: .shortened))")
        }

        statusMenu.addItem(.separator())
        statusMenu.addItem(actionItem(title: "종료", action: #selector(quitApplication)))
    }

    private func addSectionHeader(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        statusMenu.addItem(item)
    }

    private func addInfoItem(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        statusMenu.addItem(item)
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func refreshUsage() {
        store.refresh()
    }

    @objc private func toggleResetTime() {
        MenuBarPreferences.showResetTime.toggle()
        updateStatusTitle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItemManager.setEnabled(!LoginItemManager.isEnabled)
            loginItemError = nil
        } catch {
            loginItemError = "자동 실행 설정 실패: \(error.localizedDescription)"
        }
    }

    @objc private func openUsageSettings() {
        guard let url = URL(string: "https://chatgpt.com/codex/settings/usage") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}
