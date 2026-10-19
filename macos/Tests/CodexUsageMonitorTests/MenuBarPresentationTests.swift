import AppKit
import Foundation
import Testing
@testable import CodexUsageMonitor

@MainActor
struct MenuBarPresentationTests {
    @Test func unknownAndPartialSuccessKeepAllThreeProvidersVisible() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var codex = ProviderUsageState(id: .codex)
        codex.snapshot = ProviderUsageSnapshot(provider: .codex, windows: [
            ProviderUsageWindow(id: "5h", label: "단기 한도", remainingPercent: 81),
            ProviderUsageWindow(id: "7d", label: "주간 한도", remainingPercent: 24)
        ])
        codex.lastSuccess = now
        let states: [ProviderID: ProviderUsageState] = [.codex: codex]
        #expect(MenuBarPresentation.summary(states: states, now: now) == "Codex 24% · Grok — · Claude —")
        #expect(MenuBarPresentation.value(for: ProviderUsageState(id: .grok), now: now) == "—")
        var unknown = ProviderUsageState(id: .codex)
        unknown.snapshot = ProviderUsageSnapshot(provider: .codex, windows: [])
        unknown.lastSuccess = now
        #expect(MenuBarPresentation.status(for: unknown, now: now) == "응답 확인 · 수치 미제공")
    }

    @Test func staleIsVisibleAndRetainsLastSuccessfulValue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var state = ProviderUsageState(id: .codex)
        state.snapshot = ProviderUsageSnapshot(provider: .codex, windows: [
            ProviderUsageWindow(id: "weekly", label: "주간 한도", remainingPercent: 43)
        ])
        state.lastSuccess = now.addingTimeInterval(-1_201)
        #expect(MenuBarPresentation.value(for: state, now: now) == "43%*")
        #expect(MenuBarPresentation.status(for: state, now: now) == "이전 값 · 다시 확인 필요")
    }

    @Test func diagnosticsExcludeIdentityAndCredentialFields() throws {
        var state = ProviderUsageState(id: .claude)
        state.snapshot = ProviderUsageSnapshot(provider: .claude, windows: [
            ProviderUsageWindow(id: "five_hour", label: "단기 한도", remainingPercent: 64)
        ], planName: "fixture-private-identity")
        state.lastSuccess = Date(timeIntervalSince1970: 1_000_000)
        let data = try JSONSerialization.data(withJSONObject: UsageDiagnostics.payload(states: [.claude: state]))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("fixture-private-identity"))
        #expect(!text.contains("accessToken"))
        #expect(!text.contains("Authorization"))
        #expect(text.contains("remainingPercent"))
    }

    @Test func visibilityDefaultsToAllAndPreservesUserChoices() throws {
        let suiteName = "com.sundaynighttt.codex-usage-monitor.visibility-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(MenuBarPreferences.visibleProviders(in: defaults) == [.codex, .grok, .claude])
        MenuBarPreferences.registerDefaults(in: defaults)
        for id in ProviderID.allCases { #expect(MenuBarPreferences.isVisible(id, in: defaults)) }
        MenuBarPreferences.setVisible(false, for: .grok, in: defaults)
        MenuBarPreferences.setVisible(false, for: .codex, in: defaults)
        MenuBarPreferences.registerDefaults(in: defaults)
        #expect(MenuBarPreferences.visibleProviders(in: defaults) == [.claude])
        #expect(!MenuBarPreferences.isVisible(.grok, in: defaults))
        MenuBarPreferences.setVisible(false, for: .claude, in: defaults)
        MenuBarPreferences.registerDefaults(in: defaults)
        #expect(MenuBarPreferences.visibleProviders(in: defaults).isEmpty)
        MenuBarPreferences.setVisible(true, for: .codex, in: defaults)
        #expect(MenuBarPreferences.visibleProviders(in: defaults) == [.codex])
    }

    @Test func hiddenProvidersAreExcludedFromImageAndAccessibilitySummary() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let single = MenuBarPresentation.image(states: [:], now: now, showResetTime: false,
            visibleProviders: [.claude])
        let all = MenuBarPresentation.image(states: [:], now: now, showResetTime: false)
        #expect(MenuBarPresentation.summary(states: [:], now: now, visibleProviders: [.claude]) == "Claude —")
        #expect(single.accessibilityDescription == "Claude —")
        #expect(single.size.width > 19 && single.size.width < all.size.width)
        #expect(single.isTemplate)
        // Rendering also keeps the stable order if a caller supplies duplicates.
        #expect(MenuBarPresentation.summary(states: [:], now: now,
            visibleProviders: [.claude, .codex, .claude]) == "Codex — · Claude —")
    }

    @Test func hidingEveryProviderKeepsAnAccessibleVisibleMenuTarget() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fallback = MenuBarPresentation.image(states: [:], now: now, showResetTime: true,
            visibleProviders: [])
        #expect(MenuBarPresentation.summary(states: [:], now: now, visibleProviders: [])
            == "사용량 메뉴 · 표시 중인 서비스 없음")
        #expect(fallback.accessibilityDescription == "사용량 메뉴 · 표시 중인 서비스 없음")
        #expect(fallback.size.width >= 32 && fallback.size.width < 100)
        #expect(fallback.size.height == 20 && fallback.isTemplate)
        let tiff = try #require(fallback.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let containsVisibleText = (0..<bitmap.pixelsWide).contains { x in
            (0..<bitmap.pixelsHigh).contains { y in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0
            }
        }
        #expect(containsVisibleText)
    }

    @Test func bundledLogosAndTemplateRenderingAreAvailable() throws {
        for id in ProviderID.allCases {
            let logo = try #require(ProviderLogo.image(for: id))
            #expect(logo.isTemplate)
            #expect(logo.size.width > 0 && logo.size.height > 0)
        }
        let image = MenuBarPresentation.image(states: [:], now: Date(), showResetTime: false)
        #expect(image.isTemplate)
        #expect(image.size.height == 20)
        #expect(image.size.width >= 100 && image.size.width < 200)
        #expect(image.tiffRepresentation != nil)
        // Explicit opt-in creates a fixture-only visual check without live providers.
        if let path = ProcessInfo.processInfo.environment["CODEXTIME_PREVIEW_OUTPUT"],
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: path))
            let canvas = NSImage(size: NSSize(width: image.size.width + 24, height: 44))
            canvas.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: canvas.size).fill()
            image.draw(at: NSPoint(x: 12, y: 12), from: .zero, operation: .sourceOver, fraction: 1)
            canvas.unlockFocus()
            if let data = canvas.tiffRepresentation, let rendered = NSBitmapImageRep(data: data),
               let light = rendered.representation(using: .png, properties: [:]) {
                try light.write(to: URL(fileURLWithPath: path + ".light.png"))
            }
        }
    }
}
