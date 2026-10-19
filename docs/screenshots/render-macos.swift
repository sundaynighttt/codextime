import AppKit

/// Documentation-only fixtures. This executable never creates a usage client.
@main
@MainActor
enum DocumentationPreview {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)
        app.finishLaunching()
        UserDefaults.standard.setVolatileDomain([
            MenuBarPreferences.showResetTimeKey: false,
            "showProviderInMenuBar.codex": true,
            "showProviderInMenuBar.grok": true,
            "showProviderInMenuBar.claude": true
        ], forName: UserDefaults.argumentDomain)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_792_373_040)
        var states: [ProviderID: ProviderUsageState] = [:]
        for (id, percent, hours, label) in [
            (ProviderID.codex, 73, 89, "주간 한도"),
            (.grok, 82, 56, "공유 주간 한도"),
            (.claude, 64, 160, "주간 한도")
        ] {
            states[id] = ProviderUsageState(id: id, snapshot: ProviderUsageSnapshot(
                provider: id, windows: [ProviderUsageWindow(id: "weekly", label: label,
                    remainingPercent: Double(percent),
                    resetDate: now.addingTimeInterval(Double(hours) * 3_600))]),
                lastSuccess: now)
        }

        let image = MenuBarPresentation.image(states: states, now: now, showResetTime: false)
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: image.size.width + 24, height: 36))
        strip.wantsLayer = true
        strip.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let imageView = NSImageView(frame: NSRect(origin: NSPoint(x: 12, y: 8), size: image.size))
        imageView.image = image
        imageView.contentTintColor = .labelColor
        strip.addSubview(imageView)
        try save(strip, to: output.appendingPathComponent("macos-menubar-v0.3.1.png"))

        let settings = ConnectionSettingsWindow(
            onVisibilityChanged: { _, _ in }, onConnect: { _ in }, onDisconnect: { _ in },
            onOpenHelp: { _ in }, onLogin: { _ in }, onCancelLogin: {},
            onLaunchAtLoginChanged: { _ in }, onConfirmGrok: {})
        let window = settings.window!
        window.appearance = NSAppearance(named: .aqua)
        // Lay out independently of the current display's available height.
        // Hosted CI displays can be shorter than all three provider rows.
        window.setContentSize(NSSize(width: 660, height: 520))
        window.orderFront(nil)
        let content = window.contentView!
        window.contentView = nil
        window.orderOut(nil)
        content.setFrameSize(NSSize(width: 660, height: 820))
        let initial = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { id in
            (id, ProviderUsageState(id: id, failure: .authenticationRequired))
        })
        settings.update(states: initial, now: now, canConfirmGrok: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        try save(content, to: output.appendingPathComponent("macos-setup-v0.3.1.png"))
        settings.update(states: states, now: now, canConfirmGrok: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        try save(content, to: output.appendingPathComponent("macos-connected-v0.3.1.png"))
        print("Exported actual menu-bar renderer and setup views with documentation fixtures.")
    }

    private static func save(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        view.displayIgnoringOpacity(bounds, in: NSGraphicsContext.current!)
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
