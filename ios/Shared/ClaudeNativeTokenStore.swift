import Foundation
import Security
import LocalAuthentication

protocol ClaudeNativeTokenStoring: Sendable {
    func load() throws -> ClaudeNativeStoredAuth?
    func save(_ record: ClaudeNativeStoredAuth) throws
    func delete() throws
}

/// Only CodexTime's own Claude authorization is accessed. Browser and CLI stores are never read.
struct ClaudeNativeTokenStore: ClaudeNativeTokenStoring, Sendable {
    func load() throws -> ClaudeNativeStoredAuth? {
        var query = baseQuery
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 131_072,
              let record = try? JSONDecoder().decode(ClaudeNativeStoredAuth.self, from: data),
              record.hasValidFields else { throw ClaudeNativeClientError.secureStorageUnavailable }
        return record
    }

    func save(_ record: ClaudeNativeStoredAuth) throws {
        guard record.hasValidFields, let data = try? JSONEncoder().encode(record),
              data.count <= 131_072 else { throw ClaudeNativeClientError.secureStorageUnavailable }
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
                throw ClaudeNativeClientError.secureStorageUnavailable
            }
        } else if status != errSecSuccess { throw ClaudeNativeClientError.secureStorageUnavailable }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ClaudeNativeClientError.secureStorageUnavailable
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ClaudeNativeConfiguration.keychainService,
            kSecAttrAccount as String: ClaudeNativeConfiguration.keychainAccount,
            kSecAttrSynchronizable as String: false,
        ]
        if let group = CodexConfiguration.keychainAccessGroup { query[kSecAttrAccessGroup as String] = group }
        return query
    }
}
