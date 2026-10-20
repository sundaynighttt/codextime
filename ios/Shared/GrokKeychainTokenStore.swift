import Foundation
import Security

protocol GrokTokenStoring: Sendable {
    func load() throws -> GrokStoredAuth?
    func save(_ record: GrokStoredAuth) throws
    func delete() throws
}

/// Only CodexTime's own Grok authorization is accessed. Browser and CLI stores are never read.
struct GrokKeychainTokenStore: GrokTokenStoring, Sendable {
    func load() throws -> GrokStoredAuth? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 131_072,
              let record = try? JSONDecoder().decode(GrokStoredAuth.self, from: data),
              record.hasValidFields else { throw GrokClientError.secureStorageUnavailable }
        return record
    }

    func save(_ record: GrokStoredAuth) throws {
        guard record.hasValidFields, let data = try? JSONEncoder().encode(record),
              data.count <= 131_072 else { throw GrokClientError.secureStorageUnavailable }
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
                throw GrokClientError.secureStorageUnavailable
            }
        } else if status != errSecSuccess { throw GrokClientError.secureStorageUnavailable }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GrokClientError.secureStorageUnavailable
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: GrokConfiguration.keychainService,
            kSecAttrAccount as String: GrokConfiguration.keychainAccount,
            kSecAttrSynchronizable as String: false,
        ]
        if let group = CodexConfiguration.keychainAccessGroup { query[kSecAttrAccessGroup as String] = group }
        return query
    }
}
