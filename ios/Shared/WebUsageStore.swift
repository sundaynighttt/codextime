import Foundation

/// App Group storage contains bounded numeric readings, never a web session or page text.
/// Each explicitly named limit has its own record, so a session read cannot replace a week.
struct WebUsageStore: Sendable {
    private let suiteName: String

    init(suiteName: String = CodexConfiguration.appGroupID) {
        self.suiteName = suiteName
    }

    /// Compatible provider summary: Claude's all-model weekly limit takes precedence.
    /// A session-only legacy cache remains a session and is never relabeled as weekly.
    func load(_ provider: WebUsageProvider, now: Date = Date()) -> WebUsageReading? {
        preferredMetrics(for: provider).lazy.compactMap { load(provider, metric: $0, now: now) }.first
    }

    func load(_ provider: WebUsageProvider, metric: WebUsageMetric,
              now: Date = Date()) -> WebUsageReading? {
        guard metric.provider == provider else { return nil }
        // Reads are also used by a separate widget process. Never migrate/write here:
        // an in-flight widget read must not recreate data after app disconnect.
        if let data = defaults?.data(forKey: key(for: metric)) {
            return decode(data, provider: provider, metric: metric, now: now)
        }
        return decode(defaults?.data(forKey: legacyKey(for: provider)),
                      provider: provider, metric: metric, now: now)
    }

    func loadAll(now: Date = Date()) -> [WebUsageProvider: WebUsageReading] {
        WebUsageProvider.allCases.reduce(into: [:]) { result, provider in
            result[provider] = load(provider, now: now)
        }
    }

    func loadAllMetrics(now: Date = Date()) -> [WebUsageMetric: WebUsageReading] {
        WebUsageMetric.allCases.reduce(into: [:]) { result, metric in
            result[metric] = load(metric.provider, metric: metric, now: now)
        }
    }

    @discardableResult
    func save(_ reading: WebUsageReading, now: Date = Date()) -> Bool {
        guard reading.isValid(at: now),
              let data = try? JSONEncoder().encode(reading),
              data.count <= 1_024,
              let defaults else { return false }
        // The app coordinator serializes saves with disconnect on the main actor.
        // Only this explicit save path may copy a legacy value into the v2 cache.
        migrateLegacy(reading.provider, now: now)
        defaults.set(data, forKey: key(for: reading.metric))
        return true
    }

    /// Disconnect removes every limit and the old single-reading cache for this service.
    func delete(_ provider: WebUsageProvider) {
        guard let defaults else { return }
        for metric in WebUsageMetric.allCases where metric.provider == provider {
            defaults.removeObject(forKey: key(for: metric))
        }
        defaults.removeObject(forKey: legacyKey(for: provider))
    }

    private func preferredMetrics(for provider: WebUsageProvider) -> [WebUsageMetric] {
        switch provider {
        case .grok: return [.grokWeekly]
        case .claude: return [.claudeWeekly, .claudeSession]
        }
    }

    private func decode(_ data: Data?, provider: WebUsageProvider, metric: WebUsageMetric? = nil,
                        now: Date) -> WebUsageReading? {
        guard let data, data.count <= 1_024,
              let reading = try? JSONDecoder().decode(WebUsageReading.self, from: data),
              reading.provider == provider,
              metric.map({ reading.metric == $0 }) ?? true,
              reading.isValid(at: now) else { return nil }
        return reading
    }

    private func migrateLegacy(_ provider: WebUsageProvider, now: Date) {
        guard let defaults,
              let reading = decode(defaults.data(forKey: legacyKey(for: provider)),
                                   provider: provider, now: now),
              let data = try? JSONEncoder().encode(reading) else { return }
        // A newer per-limit value always wins over the previous app's single cache.
        if defaults.data(forKey: key(for: reading.metric)) == nil {
            defaults.set(data, forKey: key(for: reading.metric))
        }
        defaults.removeObject(forKey: legacyKey(for: provider))
    }

    private func key(for metric: WebUsageMetric) -> String {
        "webUsageReading.v2." + metric.provider.rawValue + "." + metric.rawValue
    }

    private func legacyKey(for provider: WebUsageProvider) -> String {
        "webUsageReading.v1." + provider.rawValue
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }
}
