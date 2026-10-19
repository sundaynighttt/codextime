import AppKit

/// An explicit review surface for the same state rendered in the menu bar.
/// Construction and updates never open the window or start a provider request.
@MainActor
final class UsageReviewWindow: NSWindowController {
    private struct ProviderRow {
        let summary: NSTextField
        let details: NSTextField
    }

    private let menuBarImage = NSImageView()
    private var rows: [ProviderID: ProviderRow] = [:]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodexTime 연결 상태"
        window.level = .normal
        window.minSize = NSSize(width: 460, height: 300)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureContent(in: window)
        update(states: [:], now: Date())
        window.center()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(states: [ProviderID: ProviderUsageState], now: Date) {
        menuBarImage.image = MenuBarPresentation.image(
            states: states, now: now, showResetTime: MenuBarPreferences.showResetTime,
            visibleProviders: MenuBarPreferences.visibleProviders
        )
        menuBarImage.setAccessibilityLabel(MenuBarPresentation.summary(states: states, now: now, visibleProviders: MenuBarPreferences.visibleProviders))

        for id in ProviderID.allCases {
            guard let row = rows[id] else { continue }
            let state = states[id] ?? ProviderUsageState(id: id)
            let value = MenuBarPresentation.value(for: state, now: now)
            let status = state.connectionIsPending
                ? "OS 권한 확인 중"
                : MenuBarPresentation.status(for: state, now: now)
            setText("\(id.name) · \(value) · \(status)", on: row.summary)

            let windows = state.snapshot?.windows ?? []
            let detailText = windows.isEmpty ? "한도 · —\n리셋 · —" : windows.map { window in
                let remaining = window.displayRemainingPercent.map { "\($0)% 남음" } ?? "—"
                let reset = window.resetDate.map {
                    $0.formatted(date: .abbreviated, time: .shortened)
                } ?? "—"
                return "\(window.label) · \(remaining)\n리셋 · \(reset)"
            }.joined(separator: "\n")
            setText(detailText, on: row.details)
        }
    }

    private func configureContent(in window: NSWindow) {
        let content = NSView()
        window.contentView = content

        menuBarImage.translatesAutoresizingMaskIntoConstraints = false
        menuBarImage.imageAlignment = .alignLeft
        menuBarImage.imageScaling = .scaleProportionallyDown
        menuBarImage.contentTintColor = .labelColor
        menuBarImage.setAccessibilityIdentifier("CodexTimeReviewMenuBarImage")
        content.addSubview(menuBarImage)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        content.addSubview(scrollView)

        let document = UsageReviewDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        document.addSubview(stack)

        for id in ProviderID.allCases {
            let summary = textField(font: .systemFont(ofSize: 13, weight: .semibold))
            summary.setAccessibilityIdentifier("CodexTimeReview-\(id.rawValue)-summary")
            let details = textField(font: .systemFont(ofSize: 12))
            details.setAccessibilityIdentifier("CodexTimeReview-\(id.rawValue)-windows")
            let row = NSStackView(views: [summary, details])
            row.translatesAutoresizingMaskIntoConstraints = false
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 5
            stack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: stack.widthAnchor),
                summary.widthAnchor.constraint(equalTo: row.widthAnchor),
                details.widthAnchor.constraint(equalTo: row.widthAnchor)
            ])
            rows[id] = ProviderRow(summary: summary, details: details)
        }

        NSLayoutConstraint.activate([
            menuBarImage.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            menuBarImage.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            menuBarImage.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            menuBarImage.heightAnchor.constraint(equalToConstant: 24),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: menuBarImage.bottomAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
    }

    private func textField(font: NSFont) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = font
        field.textColor = .labelColor
        field.isSelectable = true
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }

    private func setText(_ text: String, on field: NSTextField) {
        if field.stringValue != text { field.stringValue = text }
    }
}

private final class UsageReviewDocumentView: NSView {
    override var isFlipped: Bool { true }
}
