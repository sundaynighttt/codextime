import AppKit

/// One native status item keeps visible providers adjacent and in a stable order.
@MainActor
enum MenuBarPresentation {
    static func value(for state: ProviderUsageState, now: Date, showResetTime: Bool = false) -> String {
        guard let percent = state.displayRemainingPercent else { return "—" }
        var text = "\(percent)%"
        if state.isStale(now: now) { text += "*" }
        if showResetTime, let reset = state.snapshot?.displayWindow?.resetDate {
            text += " (\(UsageFormatter.remainingTime(until: reset, now: now)))"
        }
        return text
    }

    static func summary(
        states: [ProviderID: ProviderUsageState],
        now: Date,
        visibleProviders: [ProviderID] = ProviderID.allCases
    ) -> String {
        let providers = orderedVisibleProviders(visibleProviders)
        guard !providers.isEmpty else { return "사용량 메뉴 · 표시 중인 서비스 없음" }
        return providers.map { id in
            let state = states[id] ?? ProviderUsageState(id: id)
            let freshness = state.isStale(now: now) ? " · 이전 값" : ""
            return "\(id.name) \(value(for: state, now: now))\(freshness)"
        }.joined(separator: " · ")
    }

    static func status(for state: ProviderUsageState, now: Date) -> String {
        if state.isRefreshing { return state.snapshot == nil ? "확인 중" : "갱신 중" }
        if state.isStale(now: now) { return "이전 값 · 다시 확인 필요" }
        if state.snapshot != nil {
            return state.displayRemainingPercent == nil ? "응답 확인 · 수치 미제공" : "최신"
        }
        switch state.failure {
        case .authenticationRequired: return "로그인 필요"
        case .permissionRequired: return "연결 권한 필요"
        case .permissionDenied: return "권한 요청 취소·거부"
        case .notInstalled, .notConnected, .unsupported: return "미연결"
        case .some: return "조회 실패"
        case .none: return "조회 전"
        }
    }

    static func image(
        states: [ProviderID: ProviderUsageState], now: Date, showResetTime: Bool,
        visibleProviders: [ProviderID] = ProviderID.allCases
    ) -> NSImage {
        let providers = orderedVisibleProviders(visibleProviders)
        guard !providers.isEmpty else { return menuFallbackImage(states: states, now: now) }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let values = providers.map {
            value(for: states[$0] ?? ProviderUsageState(id: $0), now: now, showResetTime: showResetTime)
        }
        let widths = values.map { ceil(($0 as NSString).size(withAttributes: attributes).width) }
        let iconSize: CGFloat = 15
        let iconGap: CGFloat = 4
        let groupGap: CGFloat = 12
        let width = widths.reduce(0, +) + CGFloat(values.count) * (iconSize + iconGap)
            + CGFloat(values.count - 1) * groupGap
        let image = NSImage(size: NSSize(width: width, height: 20), flipped: false) { _ in
            var x: CGFloat = 0
            for (index, id) in providers.enumerated() {
                let rect = NSRect(x: x, y: 2.5, width: iconSize, height: iconSize)
                if let logo = ProviderLogo.image(for: id) {
                    logo.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                }
                x += iconSize + iconGap
                let size = (values[index] as NSString).size(withAttributes: attributes)
                (values[index] as NSString).draw(
                    at: NSPoint(x: x, y: floor((20 - size.height) / 2)), withAttributes: attributes
                )
                x += widths[index] + groupGap
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = summary(states: states, now: now, visibleProviders: providers)
        return image
    }

    private static func orderedVisibleProviders(_ requested: [ProviderID]) -> [ProviderID] {
        ProviderID.allCases.filter { requested.contains($0) }
    }

    /// The status item must remain reachable after every service is hidden.
    private static func menuFallbackImage(states: [ProviderID: ProviderUsageState], now: Date) -> NSImage {
        let title = "사용량" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor.black
        ]
        let titleSize = title.size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: max(32, ceil(titleSize.width) + 4), height: 20), flipped: false) { _ in
            title.draw(at: NSPoint(x: 2, y: floor((20 - titleSize.height) / 2)), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = summary(states: states, now: now, visibleProviders: [])
        return image
    }
}

@MainActor
enum ProviderLogo {
    static func image(for id: ProviderID) -> NSImage? {
        guard let url = Bundle.main.url(forResource: id.rawValue, withExtension: "png")
            ?? Bundle.module.url(forResource: id.rawValue, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}
