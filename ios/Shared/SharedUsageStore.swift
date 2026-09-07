import Foundation

struct SharedUsageStore: Sendable {
    private static let snapshotKey = "usageSnapshot"
    private static let demoKey = "demoUsageSnapshot"
    private let suiteName: String

    init(suiteName: String = CodexConfiguration.appGroupID) {
        self.suiteName = suiteName
    }

    var isDemoEnabled: Bool { demoSnapshot() != nil }

    func load() -> UsageSnapshot? {
        demoSnapshot() ?? decode(Self.snapshotKey)
    }

    private func decode(_ key: String) -> UsageSnapshot? {
        guard
            let data = defaults.data(forKey: key),
            let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: UsageSnapshot) {
        guard snapshot.isDemo != true else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    func delete() {
        defaults.removeObject(forKey: Self.snapshotKey)
        endDemo()
    }

    func demoSnapshot() -> UsageSnapshot? {
        guard let snapshot = decode(Self.demoKey), snapshot.isDemo == true else { return nil }
        return snapshot
    }

    func startDemo(now: Date = Date()) -> UsageSnapshot {
        let snapshot = UsageSnapshot.demo(now: now)
        saveDemo(snapshot)
        return snapshot
    }

    func refreshDemo(now: Date = Date()) -> UsageSnapshot? {
        guard let previous = demoSnapshot() else { return nil }
        let snapshot = UsageSnapshot(
            remainingPercent: previous.remainingPercent,
            resetAt: previous.resetAt,
            updatedAt: now,
            lifetimeTokens: previous.lifetimeTokens,
            isDemo: true
        )
        saveDemo(snapshot)
        return snapshot
    }

    func endDemo() {
        defaults.removeObject(forKey: Self.demoKey)
    }

    private func saveDemo(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.demoKey)
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
