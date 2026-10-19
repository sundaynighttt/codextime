import AppKit

/// Presents app-owned connection controls; all changes are handled by the caller.
@MainActor
final class ConnectionSettingsWindow: NSWindowController {
    private struct Row {
        let visible: NSButton
        let status: NSTextField
        let quota: NSTextField
        let guidance: NSTextField
        let login: NSButton
        let connect: NSButton
        let disconnect: NSButton?
        let confirm: NSButton?
    }

    private let onVisibilityChanged: (ProviderID, Bool) -> Void
    private let onConnect: (ProviderID) -> Void
    private let onDisconnect: (ProviderID) -> Void
    private let onOpenHelp: (ProviderID) -> Void
    private let onLogin: (ProviderID) -> Void
    private let onCancelLogin: () -> Void
    private let onLaunchAtLoginChanged: (Bool) -> Void
    private let onConfirmGrok: () -> Void
    private var rows: [ProviderID: Row] = [:]
    private let menuBarPreview = NSImageView()
    private let heading = NSTextField(labelWithString: "계정 연결을 시작하세요")
    private let setupSummary = NSTextField(wrappingLabelWithString: "")
    private let startup = NSButton(checkboxWithTitle: "로그인 시 자동 실행", target: nil, action: nil)
    private let finish = NSButton(title: "나중에 설정", target: nil, action: nil)
    private let cancelLogin = NSButton(title: "로그인 취소", target: nil, action: nil)

    init(
        onVisibilityChanged: @escaping (ProviderID, Bool) -> Void,
        onConnect: @escaping (ProviderID) -> Void,
        onDisconnect: @escaping (ProviderID) -> Void,
        onOpenHelp: @escaping (ProviderID) -> Void,
        onLogin: @escaping (ProviderID) -> Void,
        onCancelLogin: @escaping () -> Void,
        onLaunchAtLoginChanged: @escaping (Bool) -> Void,
        onConfirmGrok: @escaping () -> Void
    ) {
        self.onVisibilityChanged = onVisibilityChanged
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        self.onOpenHelp = onOpenHelp
        self.onLogin = onLogin
        self.onCancelLogin = onCancelLogin
        self.onLaunchAtLoginChanged = onLaunchAtLoginChanged
        self.onConfirmGrok = onConfirmGrok
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 720),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.title = "CodexTime 간편 설정"
        window.level = .normal
        window.minSize = NSSize(width: 600, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureContent(in: window)
        update(states: [:], now: Date(), canConfirmGrok: false)
        window.center()
    }

    required init?(coder: NSCoder) { return nil }

    func update(states: [ProviderID: ProviderUsageState], now: Date, canConfirmGrok: Bool,
                loginProvider: ProviderID? = nil, messages: [ProviderID: String] = [:],
                startupError: String? = nil, installedProviders: Set<ProviderID> = Set(ProviderID.allCases),
                awaitingGrokConfirmation: Bool = false) {
        menuBarPreview.image = MenuBarPresentation.image(states: states, now: now,
            showResetTime: MenuBarPreferences.showResetTime, visibleProviders: MenuBarPreferences.visibleProviders)
        menuBarPreview.setAccessibilityLabel(MenuBarPresentation.summary(states: states, now: now,
            visibleProviders: MenuBarPreferences.visibleProviders))
        var connectedCount = 0
        let selected = MenuBarPreferences.visibleProviders
        for id in ProviderID.allCases {
            guard let row = rows[id] else { continue }
            let state = states[id] ?? ProviderUsageState(id: id)
            let visible = MenuBarPreferences.isVisible(id)
            let presentation = SetupRowPresentation(state: state,
                awaitingGrokConfirmation: id == .grok && awaitingGrokConfirmation,
                dependencyInstalled: installedProviders.contains(id))
            if visible && presentation.connected { connectedCount += 1 }
            row.visible.state = visible ? .on : .off
            let status = state.connectionIsPending ? "OS 권한 확인 중"
                : MenuBarPresentation.status(for: state, now: now)
            setText(!visible ? "표시 꺼짐 · 자동 조회 중지" : id == .grok && awaitingGrokConfirmation ? "웹 대조 대기 · 자동 갱신 꺼짐" : status, on: row.status)
            let window = state.snapshot?.displayWindow ?? state.snapshot?.windows.first
            if let window {
                let value = window.displayRemainingPercent.map { "\($0)% 남음" } ?? "—"
                let reset = window.resetDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "미확인"
                let previous = state.isStale(now: now) ? " · 이전 값" : ""
                setText("\(window.label) · \(value)\(previous)\n리셋 · \(reset)", on: row.quota)
            } else {
                setText("잔여 한도 · —\n리셋 · —", on: row.quota)
            }
            let busy = state.isRefreshing || state.connectionIsPending || loginProvider == id
            row.connect.isEnabled = !busy
            row.connect.title = busy ? "확인 중…" : presentation.connectTitle
            row.login.title = presentation.loginTitle
            row.login.isHidden = !presentation.showLogin
            row.login.isEnabled = !busy && loginProvider == nil
            setText(messages[id] ?? presentation.guidance, on: row.guidance)
            if loginProvider == id { setText("공식 로그인 완료 대기 중", on: row.status) }
            row.disconnect?.isEnabled = !busy
            row.confirm?.isEnabled = canConfirmGrok && !busy
        }
        let complete = !selected.isEmpty && connectedCount == selected.count
        heading.stringValue = complete ? "설정이 완료됐습니다" : "계정 연결을 시작하세요"
        setText(startupError ?? (selected.isEmpty ? "표시할 서비스를 선택하세요."
            : complete ? "설정 완료 · 선택한 \(selected.count)개 서비스를 자동 갱신합니다."
            : "\(selected.count)개 중 \(connectedCount)개 연결 완료 · 아래에서 필요한 단계만 진행하세요."), on: setupSummary)
        startup.state = LoginItemManager.isEnabled ? .on : .off
        finish.title = complete ? "설정 완료" : "나중에 설정"
        cancelLogin.isHidden = loginProvider == nil
    }

    private func configureContent(in window: NSWindow) {
        let content = NSView()
        window.contentView = content
        let footer = NSStackView(views: [startup, NSView(), cancelLogin, finish])
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.spacing = 12
        content.addSubview(footer)
        startup.target = self
        startup.action = #selector(startupChanged(_:))
        startup.setAccessibilityIdentifier("CodexTimeSetup-startup")
        finish.target = self
        finish.action = #selector(finishSetup)
        finish.bezelStyle = .rounded
        finish.setAccessibilityIdentifier("CodexTimeSetup-finish")
        cancelLogin.target = self
        cancelLogin.action = #selector(cancelSetupLogin)
        cancelLogin.bezelStyle = .rounded
        cancelLogin.isHidden = true
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        content.addSubview(scroll)
        let document = ConnectionSettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        document.addSubview(stack)
        heading.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(heading)
        setupSummary.font = .systemFont(ofSize: 13, weight: .medium)
        setupSummary.setAccessibilityIdentifier("CodexTimeSetup-summary")
        stack.addArrangedSubview(setupSummary)
        setupSummary.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        menuBarPreview.imageAlignment = .alignLeft
        menuBarPreview.imageScaling = .scaleProportionallyDown
        menuBarPreview.contentTintColor = .labelColor
        menuBarPreview.setAccessibilityIdentifier("CodexTimeSettingsMenuBarPreview")
        stack.addArrangedSubview(menuBarPreview)
        NSLayoutConstraint.activate([
            menuBarPreview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            menuBarPreview.heightAnchor.constraint(equalToConstant: 24)
        ])
        let introduction = text(
            "① 사용할 서비스 선택  →  ② 기존 계정 연결 또는 로그인  →  ③ 사용량 확인\n로그인과 macOS 권한 승인만 직접 완료해 주세요. 표시를 끈 서비스는 조회하지 않습니다.",
            font: .systemFont(ofSize: 12), color: .secondaryLabelColor
        )
        stack.addArrangedSubview(introduction)
        introduction.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        for (index, id) in ProviderID.allCases.enumerated() {
            let separator = NSBox()
            separator.boxType = .separator
            stack.addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let row = makeRow(id: id, index: index)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -4)
        ])
    }

    private func makeRow(id: ProviderID, index: Int) -> NSStackView {
        let logo = NSImageView()
        logo.image = ProviderLogo.image(for: id)
        logo.imageScaling = .scaleProportionallyDown
        logo.contentTintColor = .labelColor
        logo.setAccessibilityLabel(id.name)
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 20),
            logo.heightAnchor.constraint(equalToConstant: 20)
        ])
        let name = text(id.name, font: .systemFont(ofSize: 14, weight: .semibold))
        let visible = NSButton(checkboxWithTitle: "메뉴 막대에 표시", target: self, action: #selector(visibilityChanged(_:)))
        visible.tag = index
        visible.setAccessibilityIdentifier("CodexTimeConnection-\(id.rawValue)-visible")
        visible.setAccessibilityLabel("\(id.name) 메뉴 막대에 표시")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [logo, name, spacer, visible])
        header.spacing = 8
        header.alignment = .centerY
        let status = text("", font: .systemFont(ofSize: 12, weight: .medium))
        status.setAccessibilityIdentifier("CodexTimeConnection-\(id.rawValue)-status")
        let quota = text("", font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular))
        quota.setAccessibilityIdentifier("CodexTimeConnection-\(id.rawValue)-quota")
        let guidance = text(guidance(for: id), font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let help = button(helpTitle(for: id), index: index, action: #selector(openHelp(_:)))
        let login = button("로그인하기", index: index, action: #selector(loginProvider(_:)))
        login.setAccessibilityIdentifier("CodexTimeConnection-\(id.rawValue)-login")
        let connect = button(connectTitle(for: id), index: index, action: #selector(connectProvider(_:)))
        connect.setAccessibilityIdentifier("CodexTimeConnection-\(id.rawValue)-connect")
        let disconnect = id == .codex ? nil : button("연결 해제", index: index, action: #selector(disconnectProvider(_:)))
        let buttons = NSStackView(views: [connect, login, help] + (disconnect.map { [$0] } ?? []))
        buttons.spacing = 8
        buttons.alignment = .centerY
        let row = NSStackView(views: [header, status, quota, guidance, buttons])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 8
        for field in [header, status, quota, guidance] {
            field.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        }
        var confirm: NSButton?
        if id == .grok {
            let control = button("웹 값과 일치함 · 자동 갱신", index: index, action: #selector(confirmGrok))
            control.setAccessibilityIdentifier("CodexTimeConnection-grok-confirm")
            row.addArrangedSubview(control)
            confirm = control
        }
        rows[id] = Row(visible: visible, status: status, quota: quota, guidance: guidance, login: login, connect: connect,
                       disconnect: disconnect, confirm: confirm)
        return row
    }

    private func text(_ value: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = font
        field.textColor = color
        field.isSelectable = true
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }

    private func button(_ title: String, index: Int, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.tag = index
        return button
    }

    private func setText(_ value: String, on field: NSTextField) {
        if field.stringValue != value { field.stringValue = value }
    }

    private func provider(for sender: NSButton) -> ProviderID? {
        let ids = ProviderID.allCases
        return ids.indices.contains(sender.tag) ? ids[sender.tag] : nil
    }

    @objc private func visibilityChanged(_ sender: NSButton) {
        if let id = provider(for: sender) { onVisibilityChanged(id, sender.state == .on) }
    }
    @objc private func connectProvider(_ sender: NSButton) {
        if let id = provider(for: sender) { onConnect(id) }
    }
    @objc private func disconnectProvider(_ sender: NSButton) {
        if let id = provider(for: sender) { onDisconnect(id) }
    }
    @objc private func openHelp(_ sender: NSButton) {
        if let id = provider(for: sender) { onOpenHelp(id) }
    }
    @objc private func loginProvider(_ sender: NSButton) {
        if let id = provider(for: sender) { onLogin(id) }
    }
    @objc private func startupChanged(_ sender: NSButton) { onLaunchAtLoginChanged(sender.state == .on) }
    @objc private func finishSetup() { close() }
    @objc private func cancelSetupLogin() { onCancelLogin() }
    @objc private func confirmGrok() { onConfirmGrok() }

    private func connectTitle(for id: ProviderID) -> String {
        switch id {
        case .codex: return "새로고침"
        case .grok: return "Cursor로 연결…"
        case .claude: return "Claude 연결…"
        }
    }
    private func helpTitle(for id: ProviderID) -> String {
        switch id {
        case .codex: return "설치·로그인 안내"
        case .grok: return "웹 사용량 열기"
        case .claude: return "로그인 안내"
        }
    }
    private func guidance(for id: ProviderID) -> String {
        switch id {
        case .codex: return "Codex CLI를 설치하고 codex login을 완료한 뒤 새로고침하세요."
        case .grok: return "Cursor에서 본인 계정으로 로그인한 뒤 연결하세요. 조회 후 grok.com 사용량과 대조합니다."
        case .claude: return "Claude Code에서 구독 계정으로 로그인한 뒤 연결 권한을 허용하세요."
        }
    }
}

private final class ConnectionSettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
