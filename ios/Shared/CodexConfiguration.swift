import Foundation

enum CodexConfiguration {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let authBaseURL = URL(string: "https://auth.openai.com")!
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let appGroupID = "group.com.sundaynighttt.codextime"
    static let keychainGroupSuffix = "com.sundaynighttt.codextime.auth"
    static let keychainService = "com.sundaynighttt.codextime.tokens"
    static let keychainAccount = "chatgpt"

    static var keychainAccessGroup: String? {
        guard
            let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
            !prefix.isEmpty
        else {
            return nil
        }
        return prefix + keychainGroupSuffix
    }
}
