import Foundation

enum MenuBarPreferences {
    static let showResetTimeKey = "showResetTimeInMenuBar"

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        var values: [String: Any] = [showResetTimeKey: false]
        for id in ProviderID.allCases { values[visibilityKey(for: id)] = true }
        defaults.register(defaults: values)
    }

    static func isVisible(_ id: ProviderID, in defaults: UserDefaults = .standard) -> Bool {
        // Existing installations and first reads default to all services visible.
        defaults.object(forKey: visibilityKey(for: id)) as? Bool ?? true
    }

    static func setVisible(_ visible: Bool, for id: ProviderID, in defaults: UserDefaults = .standard) {
        defaults.set(visible, forKey: visibilityKey(for: id))
    }

    static var visibleProviders: [ProviderID] { visibleProviders(in: .standard) }

    static func visibleProviders(in defaults: UserDefaults) -> [ProviderID] {
        ProviderID.allCases.filter { isVisible($0, in: defaults) }
    }

    private static func visibilityKey(for id: ProviderID) -> String {
        "showProviderInMenuBar.\(id.rawValue)"
    }

    static var showResetTime: Bool {
        get { UserDefaults.standard.bool(forKey: showResetTimeKey) }
        set { UserDefaults.standard.set(newValue, forKey: showResetTimeKey) }
    }
}
