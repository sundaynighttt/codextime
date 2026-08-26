import Foundation

enum MenuBarPreferences {
    static let showResetTimeKey = "showResetTimeInMenuBar"

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [showResetTimeKey: false])
    }

    static var showResetTime: Bool {
        get { UserDefaults.standard.bool(forKey: showResetTimeKey) }
        set { UserDefaults.standard.set(newValue, forKey: showResetTimeKey) }
    }
}
