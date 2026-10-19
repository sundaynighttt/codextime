import SwiftUI
import UsageSync

// Codex is queried on this iPhone. Other supported results arrive only through opt-in private iCloud sync.
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
    let cloudReading: SyncedUsage?
    let cloudEnabled: Bool
    let cloudHadError: Bool
    let now: Date

    init(provider: PhoneUsageProvider, snapshot: UsageSnapshot?, cloudReading: SyncedUsage? = nil,
         cloudEnabled: Bool = false, cloudHadError: Bool = false, now: Date = Date()) {
        self.provider = provider
        self.snapshot = snapshot
        self.cloudReading = cloudReading
        self.cloudEnabled = cloudEnabled
        self.cloudHadError = cloudHadError
        self.now = now
    }

    var id: PhoneUsageProvider { provider }
    private var availableCloudReading: SyncedUsage? {
        guard provider == .grok, snapshot?.isDemo != true, cloudEnabled, let reading = cloudReading,
              reading.provider == .grok, reading.status == .ready,
              let percent = reading.remainingPercent, (0...100).contains(percent),
              let observedAt = reading.observedAt, observedAt <= now.addingTimeInterval(300) else { return nil }
        return reading
    }
    var percentText: String {
        switch provider {
        case .codex: return snapshot.map { "\($0.remainingPercent)%" } ?? "—"
        case .grok: return availableCloudReading?.remainingPercent.map { "\($0)%" } ?? "—"
        case .claude: return "—"
        }
    }
    var statusText: String {
        switch provider {
        case .codex:
            guard let snapshot else { return "연결 필요" }
            return snapshot.isDemo == true ? "예시" : "연결됨"
        case .claude:
            return "허용 확인"
        case .grok:
            guard snapshot?.isDemo != true else { return "예시 · 일시 정지" }
            guard cloudEnabled else { return "iCloud 연결" }
            if let reading = availableCloudReading {
                if cloudHadError { return "연결 오류 · 캐시" }
                return reading.isStale(at: now) ? "오래된 정보" : "Mac에서 동기화"
            }
            if cloudHadError { return "동기화 오류" }
            switch cloudReading?.status {
            case .disconnected: return "Mac 연결 필요"
            case .paused: return "Mac에서 일시 정지"
            case .blocked: return "연결 확인 필요"
            case .failed: return "Mac 조회 오류"
            default: return "Mac 데이터 대기"
            }
        }
    }
    var accessibilityText: String {
        switch provider {
        case .codex:
            guard let snapshot else { return "Codex, 잔여량 없음, ChatGPT 연결 필요" }
            return "Codex, \(snapshot.isDemo == true ? "예시 데이터, " : "")\(snapshot.remainingPercent)퍼센트 남음"
        case .claude:
            return "Claude, 잔여량 없음, 공급자 허용 확인이 필요하여 연결 차단됨"
        case .grok:
            guard snapshot?.isDemo != true else { return "Grok, 잔여량 없음, 예시 보기 중 iCloud 동기화 일시 정지" }
            guard let reading = availableCloudReading, let percent = reading.remainingPercent else {
                return "Grok, 잔여량 없음, \(statusText)"
            }
            let updated = reading.observedAt.map { ", 조회 시각 " + UsageFormatter.updateTime($0) } ?? ""
            return "Grok, \(percent)퍼센트 남음, \(statusText)" + updated
        }
    }
}

struct ProviderUsageColumns: View {
    let snapshot: UsageSnapshot?
    let now: Date
    var compact = false
    var cloudReadings: [SyncProvider: SyncedUsage] = [:]
    var cloudEnabled = false
    var cloudHadError = false
    @ScaledMetric(relativeTo: .title) private var percentSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 4 : 12) {
            ForEach(PhoneUsageProvider.allCases) { provider in
                let display = ProviderUsageDisplay(
                    provider: provider, snapshot: snapshot, cloudReading: cloudReadings[.grok],
                    cloudEnabled: cloudEnabled, cloudHadError: cloudHadError, now: now
                )
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
