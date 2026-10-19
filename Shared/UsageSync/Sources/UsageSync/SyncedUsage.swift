import Foundation

public enum SyncProvider: String, Codable, CaseIterable, Sendable {
    case grok, claude
}

public enum SyncReadingStatus: String, Codable, Sendable {
    case ready, disconnected, paused, blocked, failed
}

/// This value is the complete transfer allowlist. It cannot contain credentials,
/// account identifiers, device names, provider responses, or error descriptions.
public struct SyncedUsage: Codable, Equatable, Sendable {
    public let provider: SyncProvider
    public let remainingPercent: Int?
    public let resetAt: Date?
    public let observedAt: Date?
    public let status: SyncReadingStatus

    public init(provider: SyncProvider, remainingPercent: Int?, resetAt: Date?, observedAt: Date?, status: SyncReadingStatus) {
        self = Self.sanitized(provider: provider, remainingPercent: remainingPercent, resetAt: resetAt, observedAt: observedAt, status: status, now: Date())
    }

    private init(uncheckedProvider provider: SyncProvider, remainingPercent: Int?, resetAt: Date?, observedAt: Date?, status: SyncReadingStatus) {
        self.provider = provider
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
        self.observedAt = observedAt
        self.status = status
    }

    private static func sanitized(provider: SyncProvider, remainingPercent: Int?, resetAt: Date?, observedAt: Date?, status: SyncReadingStatus, now: Date) -> Self {
        // Claude's present authentication route is not authorized for this sync.
        // Enforce the restriction in the serialization boundary, not only the UI.
        if provider == .claude {
            return Self(uncheckedProvider: provider, remainingPercent: nil, resetAt: nil, observedAt: nil, status: .blocked)
        }
        guard status == .ready else {
            return Self(uncheckedProvider: provider, remainingPercent: nil, resetAt: nil, observedAt: nil, status: status)
        }
        guard let percent = remainingPercent, (0...100).contains(percent),
              let observed = observedAt,
              observed.timeIntervalSince1970.isFinite,
              observed.timeIntervalSince1970 >= 0,
              observed <= now.addingTimeInterval(300),
              resetAt.map({ $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 >= 0 && $0 <= now.addingTimeInterval(366 * 86_400) }) ?? true else {
            return Self(uncheckedProvider: provider, remainingPercent: nil, resetAt: nil, observedAt: nil, status: .failed)
        }
        return Self(uncheckedProvider: provider, remainingPercent: percent, resetAt: resetAt, observedAt: observed, status: status)
    }

    /// Staleness is computed from the provider's observation, never cloud upload time.
    public func isStale(at now: Date = Date(), maxAge: TimeInterval = 1_200) -> Bool {
        guard status == .ready, let observedAt, maxAge.isFinite, maxAge >= 0 else { return true }
        return now.timeIntervalSince(observedAt) > maxAge || observedAt > now.addingTimeInterval(300)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case provider, remainingPercent, resetAt, observedAt, status
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: AnyKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard all.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected usage field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(provider: try values.decode(SyncProvider.self, forKey: .provider),
                  remainingPercent: try values.decodeIfPresent(Int.self, forKey: .remainingPercent),
                  resetAt: try values.decodeIfPresent(Date.self, forKey: .resetAt),
                  observedAt: try values.decodeIfPresent(Date.self, forKey: .observedAt),
                  status: try values.decode(SyncReadingStatus.self, forKey: .status))
    }
}

public enum CloudSyncState: String, Equatable, Sendable {
    case disabled, ready, syncing, signedOut, notConfigured, networkError, deletionPending

    public var message: String {
        switch self {
        case .disabled: return "iCloud 동기화 꺼짐"
        case .ready: return "본인 iCloud에 동기화됨"
        case .syncing: return "iCloud 동기화 중"
        case .signedOut: return "기기 설정에서 iCloud에 로그인해 주세요"
        case .notConfigured: return "이 빌드는 iCloud 동기화를 지원하지 않습니다"
        case .networkError: return "iCloud에 연결할 수 없습니다. 마지막 조회 시각을 확인해 주세요"
        case .deletionPending: return "동기화는 꺼졌습니다. iCloud 데이터 삭제를 다시 시도해 주세요"
        }
    }
}

public enum UsageSyncError: Error, Sendable {
    case notConfigured, signedOut, accountChanged, network, invalidPayload
}
