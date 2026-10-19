import AppKit

/// Presents app-owned connection controls; all changes are handled by the caller.
@MainActor
final class ConnectionSettingsWindow: NSWindowController {
    private struct Row {
        let visible: NSButton
        let status: NSTextField
        let quota: NSTextField
        let connect: NSButton
        let disconnect: NSButton?
        let confirm: NSButton?
    }

    private let onVisibilityChanged: (ProviderID, Bool) -> Void
    private let onConnect: (ProviderID) -> Void
    private let onDisconnect: (ProviderID) -> Void
    private let onOpenHelp: (ProviderID) -> Void
    private let onConfirmGrok: () -> Void
    private let onCloudEnabledChanged: (Bool) -> Void
    private let onCloudRefresh: () -> Void
    private let onCloudDelete: () -> Void
    private let cloudToggle = NSButton(checkboxWithTitle: "본인 iCloud로 iPhone에 동기화", target: nil, action: nil)
    private let cloudStatus = NSTextField(wrappingLabelWithString: "iCloud 동기화 꺼짐")
    private var rows: [ProviderID: Row] = [:]
    private let menuBarPreview = NSImageView()

    init(
        onVisibilityChanged: @escaping (ProviderID, Bool) -> Void,
        onConnect: @escaping (ProviderID) -> Void,
        onDisconnect: @escaping (ProviderID) -> Void,
        onOpenHelp: @escaping (ProviderID) -> Void,
        onConfirmGrok: @escaping () -> Void,
        onCloudEnabledChanged: @escaping (Bool) -> Void,
        onCloudRefresh: @escaping () -> Void,
        onCloudDelete: @escaping () -> Void
    ) {
        self.onVisibilityChanged = onVisibilityChanged
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        self.onOpenHelp = onOpenHelp
        self.onConfirmGrok = onConfirmGrok
        self.onCloudEnabledChanged = onCloudEnabledChanged
        self.onCloudRefresh = onCloudRefresh
        self.onCloudDelete = onCloudDelete
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 620),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.title = "계정 연결 및 표시"
        window.level = .normal
        window.minSize = NSSize(width: 540, height: 420)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureContent(in: window)
        update(states: [:], now: Date(), canConfirmGrok: false)
        window.center()
    }

    required init?(coder: NSCoder) { return nil }

    func update(states: [ProviderID: ProviderUsageState], now: Date, canConfirmGrok: Bool) {
        menuBarPreview.image = MenuBarPresentation.image(states: states, now: now,
            showResetTime: MenuBarPreferences.showResetTime, visibleProviders: MenuBarPreferences.visibleProviders)
        menuBarPreview.setAccessibilityLabel(MenuBarPresentation.summary(states: states, now: now,
            visibleProviders: MenuBarPreferences.visibleProviders))
        for id in ProviderID.allCases {
            guard let row = rows[id] else { continue }
            let state = states[id] ?? ProviderUsageState(id: id)
            let visible = MenuBarPreferences.isVisible(id)
            row.visible.state = visible ? .on : .off
            let status = state.connectionIsPending ? "OS 권한 확인 중"
                : MenuBarPresentation.status(for: state, now: now)
            setText(!visible ? "표시 꺼짐 · 자동 조회 중지" : id == .grok && canConfirmGrok ? "웹 대조 대기 · 자동 갱신 꺼짐" : status, on: row.status)
            let window = state.snapshot?.displayWindow ?? state.snapshot?.windows.first
            if let window {
                let value = window.displayRemainingPercent.map { "\($0)% 남음" } ?? "—"
                let reset = window.resetDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "미확인"
                let previous = state.isStale(now: now) ? " · 이전 값" : ""
                setText("\(window.label) · \(value)\(previous)\n리셋 · \(reset)", on: row.quota)
            } else {
                setText("잔여 한도 · —\n리셋 · —", on: row.quota)
            }
            let busy = state.isRefreshing || state.connectionIsPending
            row.connect.isEnabled = !busy && id != .claude
            row.connect.title = busy ? "확인 중…" : connectTitle(for: id)
            row.disconnect?.isEnabled = !busy
            row.confirm?.isEnabled = canConfirmGrok && !busy
        }
    }

    func updateCloud(isEnabled: Bool, message: String) {
        cloudToggle.state = isEnabled ? .on : .off
        setText(message, on: cloudStatus)
    }

    private func configureContent(in window: NSWindow) {
        let content = NSView()
        window.contentView = content
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
            "표시를 끄면 자동 조회도 멈춥니다. 계정 변경 후에는 연결을 해제하고 다시 연결하세요.",
            font: .systemFont(ofSize: 12), color: .secondaryLabelColor
        )
        stack.addArrangedSubview(introduction)
        introduction.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let cloudSection = makeCloudSection()
        stack.addArrangedSubview(cloudSection)
        cloudSection.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -4)
        ])
    }

    private func makeCloudSection() -> NSStackView {
        cloudToggle.target = self
        cloudToggle.action = #selector(cloudEnabledChanged(_:))
        cloudToggle.setAccessibilityIdentifier("CodexTimeCloudSync-enabled")
        cloudStatus.font = .systemFont(ofSize: 12, weight: .medium)
        cloudStatus.isSelectable = true
        cloudStatus.setAccessibilityIdentifier("CodexTimeCloudSync-status")
        let description = text(
            "같은 Apple 계정의 비공개 iCloud에 Grok 잔여율·리셋·조회 시각·상태만 보냅니다. 토큰·비밀번호는 Mac에 남습니다. 최신 값에는 Mac 실행이 필요하며, Claude는 공급자 제한으로 조회가 중지됩니다.",
            font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let refresh = button("지금 동기화", index: 0, action: #selector(refreshCloud))
        let delete = button("끄고 iCloud 값 삭제", index: 0, action: #selector(deleteCloud))
        delete.setAccessibilityIdentifier("CodexTimeCloudSync-disable-delete")
        let controls = NSStackView(views: [refresh, delete])
        controls.spacing = 8
        let section = NSStackView(views: [cloudToggle, cloudStatus, description, controls])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        for view in [cloudStatus, description] {
            view.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        return section
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
        let connect = button(connectTitle(for: id), index: index, action: #selector(connectProvider(_:)))
        connect.setAccessibilityIdentifier("CodexTimeConnection-\(id.rawValue)-connect")
        let disconnect = id == .codex ? nil : button("연결 해제", index: index, action: #selector(disconnectProvider(_:)))
        let buttons = NSStackView(views: [help, connect] + (disconnect.map { [$0] } ?? []))
        if id == .claude {
            buttons.addArrangedSubview(button("이용 제한 안내", index: index, action: #selector(openClaudePolicy)))
        }
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
        rows[id] = Row(visible: visible, status: status, quota: quota, connect: connect,
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
    @objc private func openClaudePolicy() {
        if let url = URL(string: ProviderConnectionGuidance.claudePolicyURL) { NSWorkspace.shared.open(url) }
    }
    @objc private func confirmGrok() { onConfirmGrok() }
    @objc private func cloudEnabledChanged(_ sender: NSButton) { onCloudEnabledChanged(sender.state == .on) }
    @objc private func refreshCloud() { onCloudRefresh() }
    @objc private func deleteCloud() { onCloudDelete() }

    private func connectTitle(for id: ProviderID) -> String {
        switch id {
        case .codex: return "새로고침"
        case .grok: return "Cursor로 연결…"
        case .claude: return "공급자 허용 필요"
        }
    }
    private func helpTitle(for id: ProviderID) -> String {
        switch id {
        case .codex: return "설치·로그인 안내"
        case .grok: return "웹 사용량 열기"
        case .claude: return "공식 사용량 열기"
        }
    }
    private func guidance(for id: ProviderID) -> String {
        switch id {
        case .codex: return "Codex CLI를 설치하고 codex login을 완료한 뒤 새로고침하세요."
        case .grok: return "Cursor에서 본인 계정으로 로그인한 뒤 연결하세요. 조회 후 grok.com 사용량과 대조합니다."
        case .claude: return ProviderConnectionGuidance.claudeRestrictionMessage
        }
    }
}

private final class ConnectionSettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
