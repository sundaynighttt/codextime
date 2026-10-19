import SwiftUI

// Presentation only: iPhone currently has a Codex data source, not a shared Mac feed.
enum PhoneUsageProvider: String, CaseIterable, Identifiable {
    case codex, grok, claude

    var id: String { rawValue }
    var name: String {
        switch self {
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .claude: return "Claude"
        }
    }
    var logoName: String { "provider-" + rawValue }
}

struct ProviderUsageDisplay: Identifiable {
    let provider: PhoneUsageProvider
    let snapshot: UsageSnapshot?

    var id: PhoneUsageProvider { provider }
    private var availableSnapshot: UsageSnapshot? {
        provider == .codex ? snapshot : nil
    }
    var percentText: String {
        guard let snapshot = availableSnapshot else { return "—" }
        return "\(snapshot.remainingPercent)%"
    }
    var statusText: String {
        guard provider == .codex else { return "미지원" }
        guard let snapshot = availableSnapshot else { return "연결 필요" }
        return snapshot.isDemo == true ? "예시" : "연결됨"
    }
    var accessibilityText: String {
        guard provider == .codex else { return "\(provider.name), 잔여량 없음, iPhone 연결 미지원" }
        guard let snapshot = availableSnapshot else { return "Codex, 잔여량 없음, ChatGPT 연결 필요" }
        return "Codex, \(snapshot.isDemo == true ? "예시 데이터, " : "")\(snapshot.remainingPercent)퍼센트 남음"
    }
}

struct ProviderUsageColumns: View {
    let snapshot: UsageSnapshot?
    let now: Date
    var compact = false
    @ScaledMetric(relativeTo: .title) private var percentSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 4 : 12) {
            ForEach(PhoneUsageProvider.allCases) { provider in
                let display = ProviderUsageDisplay(provider: provider, snapshot: snapshot)
                VStack(spacing: compact ? 5 : 8) {
                    Image(provider.logoName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: compact ? 18 : 24, height: compact ? 18 : 24)
                        .accessibilityHidden(true)

                    Text(provider.name)
                        .font(compact ? .system(size: 9, weight: .medium) : .caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(display.percentText)
                        .font(.system(size: compact ? 20 : min(percentSize, 40), weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .invalidatableContent()

                    Text(display.statusText)
                        .font(compact ? .system(size: 9) : .caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(display.accessibilityText)
                .accessibilityIdentifier("provider-" + provider.rawValue)
            }
        }
    }
}
