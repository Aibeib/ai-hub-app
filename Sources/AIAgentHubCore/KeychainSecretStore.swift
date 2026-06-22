import Foundation
#if canImport(Security)
import Security
#endif

public enum KeychainSecretStoreError: Error, Equatable {
    case unsupportedPlatform
    case unhandledStatus(Int32)
    case invalidData
}

public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.local.AIAgentHub.secrets") {
        self.service = service
    }

    public func save(_ value: String, for key: String) throws {
        guard !key.isEmpty else {
            throw SecretStoreError.invalidKey
        }

        #if canImport(Security)
        let data = Data(value.utf8)
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainSecretStoreError.unhandledStatus(status)
        }
        #else
        throw KeychainSecretStoreError.unsupportedPlatform
        #endif
    }

    public func read(_ key: String) throws -> String? {
        guard !key.isEmpty else {
            throw SecretStoreError.invalidKey
        }

        #if canImport(Security)
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSecretStoreError.unhandledStatus(status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainSecretStoreError.invalidData
        }
        return value
        #else
        throw KeychainSecretStoreError.unsupportedPlatform
        #endif
    }

    public func delete(_ key: String) throws {
        guard !key.isEmpty else {
            throw SecretStoreError.invalidKey
        }

        #if canImport(Security)
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.unhandledStatus(status)
        }
        #else
        throw KeychainSecretStoreError.unsupportedPlatform
        #endif
    }

    #if canImport(Security)
    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
    #endif
}

