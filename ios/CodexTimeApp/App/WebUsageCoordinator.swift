import Combine
import Foundation
import WidgetKit

/// Owns the two ephemeral WebKit sessions for this app lifetime, separately from Codex auth.
@MainActor
final class WebUsageCoordinator: ObservableObject {
    @Published private(set) var readings: [WebUsageProvider: WebUsageReading]
    private let store: WebUsageStore
    private var models: [WebUsageProvider: ProviderWebUsageModel] = [:]

    init(store: WebUsageStore = WebUsageStore()) {
        self.store = store
        readings = store.loadAll()
    }

    func model(for provider: WebUsageProvider) -> ProviderWebUsageModel {
        if let model = models[provider] { return model }
        let model = ProviderWebUsageModel(provider: provider)
        model.onReading = { [weak self] reading in
            guard reading.provider == provider else { return }
            self?.accept(reading)
        }
        model.onDisconnect = { [weak self] in
            self?.clear(provider)
        }
        models[provider] = model
        return model
    }

    func accept(_ reading: WebUsageReading, now: Date = Date()) {
        guard store.save(reading, now: now) else { return }
        readings[reading.provider] = reading
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexTimeWidget")
    }

    func disconnect(_ provider: WebUsageProvider) {
        if let model = models[provider] {
            model.disconnect()
        } else {
            clear(provider)
        }
    }

    private func clear(_ provider: WebUsageProvider) {
        store.delete(provider)
        readings.removeValue(forKey: provider)
        // Retain the closed model: an open sheet can reopen its WebKit session,
        // and that same session must still belong to the coordinator after dismissal.
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexTimeWidget")
    }
}
