import Foundation

struct SharedUsageStore: Sendable {
    private static let snapshotKey = "usageSnapshot"

    func load() -> UsageSnapshot? {
        guard
            let data = defaults.data(forKey: Self.snapshotKey),
            let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    func delete() {
        defaults.removeObject(forKey: Self.snapshotKey)
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: CodexConfiguration.appGroupID) ?? .standard
    }
}
