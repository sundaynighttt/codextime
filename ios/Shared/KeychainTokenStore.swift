import Foundation
import Security

struct KeychainTokenStore: Sendable {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() throws -> AuthTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CodexClientError.message("보안 저장소를 읽을 수 없습니다.")
        }
        return try decoder.decode(AuthTokens.self, from: data)
    }

    func save(_ tokens: AuthTokens) throws {
        let data = try encoder.encode(tokens)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CodexClientError.message("로그인 정보를 저장할 수 없습니다.")
            }
        } else if status != errSecSuccess {
            throw CodexClientError.message("로그인 정보를 갱신할 수 없습니다.")
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CodexClientError.message("로그인 정보를 삭제할 수 없습니다.")
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: CodexConfiguration.keychainService,
            kSecAttrAccount as String: CodexConfiguration.keychainAccount,
            kSecAttrSynchronizable as String: false,
        ]
        if let accessGroup = CodexConfiguration.keychainAccessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
