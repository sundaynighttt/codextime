import Foundation

/// App Group storage contains a bounded numeric reading, never a web session or page text.
struct WebUsageStore: Sendable {
    private let suiteName: String

    init(suiteName: String = CodexConfiguration.appGroupID) {
        self.suiteName = suiteName
    }

    func load(_ provider: WebUsageProvider, now: Date = Date()) -> WebUsageReading? {
        guard let data = defaults?.data(forKey: key(for: provider)),
              data.count <= 1_024,
              let reading = try? JSONDecoder().decode(WebUsageReading.self, from: data),
              reading.provider == provider,
              reading.isValid(at: now) else { return nil }
        return reading
    }

    func loadAll(now: Date = Date()) -> [WebUsageProvider: WebUsageReading] {
        WebUsageProvider.allCases.reduce(into: [:]) { result, provider in
            result[provider] = load(provider, now: now)
        }
    }

    @discardableResult
    func save(_ reading: WebUsageReading, now: Date = Date()) -> Bool {
        guard reading.isValid(at: now),
              let data = try? JSONEncoder().encode(reading),
              data.count <= 1_024,
              let defaults else { return false }
        defaults.set(data, forKey: key(for: reading.provider))
        return true
    }

    func delete(_ provider: WebUsageProvider) {
        defaults?.removeObject(forKey: key(for: provider))
    }

    private func key(for provider: WebUsageProvider) -> String {
        "webUsageReading.v1." + provider.rawValue
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
}
