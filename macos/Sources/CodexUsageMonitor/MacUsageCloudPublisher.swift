import Foundation
import UsageSync

/// Builds only the result fields approved for the user's private iCloud data.
/// It cannot access provider credentials, account identifiers, raw replies or
/// detailed usage windows. Codex keeps its existing direct iPhone connection.
enum MacUsageCloudSnapshot {
    static func readings(
        states: [ProviderID: ProviderUsageState],
        enabledProviders: Set<ProviderID>,
        isGrokVerified: Bool
    ) -> [SyncedUsage] {
        let grok: SyncedUsage
        if !enabledProviders.contains(.grok) {
            grok = unavailable(.grok, status: .paused)
        } else if !isGrokVerified {
            grok = unavailable(.grok, status: .disconnected)
        } else if let state = states[.grok], let failure = state.failure {
            let status: SyncReadingStatus
            switch failure {
            case .authenticationRequired, .notConnected, .notInstalled: status = .disconnected
            case .unsupported: status = .blocked
            default: status = .failed
            }
            grok = unavailable(.grok, status: status)
        } else if let state = states[.grok], let window = state.snapshot?.displayWindow,
                  let percent = window.displayRemainingPercent, let observedAt = state.lastSuccess {
            grok = SyncedUsage(provider: .grok, remainingPercent: percent,
                resetAt: window.resetDate, observedAt: observedAt, status: .ready)
        } else {
            grok = unavailable(.grok, status: .disconnected)
        }
        // No existing or cached Claude quota crosses this new boundary. The
        // unsupported authentication path is blocked independently of consent.
        return [grok, unavailable(.claude, status: .blocked)]
    }

    private static func unavailable(_ provider: SyncProvider, status: SyncReadingStatus) -> SyncedUsage {
        SyncedUsage(provider: provider, remainingPercent: nil, resetAt: nil, observedAt: nil, status: status)
    }
}

/// One owned publisher drains the latest state in order. Rapid hide/disconnect
/// actions cannot leave a previous ready value as the final queued publication.
/// Repeated clock/menu updates do not issue additional network requests.
@MainActor
final class MacUsageCloudPublisher {
    private let sync: UsageCloudSync
    private var pending: [SyncedUsage]?
    private var lastSubmitted: [SyncedUsage]?
    private var worker: Task<Void, Never>?

    init(sync: UsageCloudSync) { self.sync = sync }

    func enqueue(_ readings: [SyncedUsage], force: Bool = false) {
        guard sync.isEnabled else {
            pending = nil
            lastSubmitted = nil
            return
        }
        guard force || readings != pending && readings != lastSubmitted else { return }
        pending = readings
        startWorkerIfNeeded()
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, pending != nil, sync.isEnabled else { return }
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.sync.isEnabled, let next = self.pending {
                self.pending = nil
                self.lastSubmitted = next
                await self.sync.publish(next)
            }
            self.worker = nil
            if self.pending != nil, self.sync.isEnabled { self.startWorkerIfNeeded() }
        }
    }

    func stopPending() {
        pending = nil
        lastSubmitted = nil
        worker?.cancel()
    }
}
