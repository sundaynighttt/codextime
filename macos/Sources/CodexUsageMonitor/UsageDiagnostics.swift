import AppKit
import Darwin
import Foundation

/// Runs the real app's clients. The output schema contains quota metadata only;
/// credentials and raw server/OS errors never cross the app boundary.
@MainActor
enum UsageDiagnostics {
    static func run(requestAccess: Bool, grokOnly: Bool = false) {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            let providers: [ProviderID] = grokOnly ? [.grok] : ProviderID.allCases
            let store = UsageStore(clients: ProductionUsageProviders.clients, automaticallyStart: false)
            for id in providers {
                if requestAccess && id != .codex {
                    store.connect(id, using: ProductionUsageProviders.interactiveClient(for: id))
                } else {
                    store.refresh(id)
                }
                await store.refreshAndWait(id)
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload(states: store.states, providers: providers), options: [.sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data([0x0A]))
            }
            await store.shutdown()
            exit(0)
        }
        application.run()
    }

    static func payload(states: [ProviderID: ProviderUsageState], providers: [ProviderID] = ProviderID.allCases) -> [[String: Any]] {
        providers.map { id in
            let state = states[id] ?? ProviderUsageState(id: id)
            var result: [String: Any] = ["provider": id.rawValue, "connected": state.snapshot != nil]
            result["remainingPercent"] = state.displayRemainingPercent ?? NSNull() as Any
            if let success = state.lastSuccess { result["lastSuccess"] = ISO8601DateFormatter().string(from: success) }
            if let failure = state.failure {
                result["error"] = id == .claude && failure == .unsupported
                    ? ProviderConnectionGuidance.claudeRestrictionMessage : failure.errorDescription
            }
            result["windows"] = state.snapshot?.windows.map { window in
                var item: [String: Any] = ["label": window.label]
                item["remainingPercent"] = window.displayRemainingPercent ?? NSNull() as Any
                item["remainingPercentExact"] = window.remainingPercent ?? NSNull() as Any
                if let date = window.resetDate { item["resetsAt"] = ISO8601DateFormatter().string(from: date) }
                return item
            } ?? []
            return result
        }
    }
}
