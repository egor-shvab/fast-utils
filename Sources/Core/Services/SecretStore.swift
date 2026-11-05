import Foundation
import Security

/// Storage for secrets such as API keys. Never log values read from here.
@MainActor
public protocol SecretStore: AnyObject {
    func secret(for key: String) -> String?
    /// Passing `nil` deletes the secret.
    func setSecret(_ value: String?, for key: String) throws
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Generic-password items in the login keychain, service = bundle id.
@MainActor
public final class KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = AppInfo.bundleIdentifier) {
        self.service = service
    }

    public func secret(for key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ value: String?, for key: String) throws {
        let deleteStatus = SecItemDelete(baseQuery(key) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError(status: deleteStatus)
        }
        guard let value else { return }
        var item = baseQuery(key)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

/// In-memory implementation for tests.
@MainActor
public final class InMemorySecretStore: SecretStore {
    private var values: [String: String] = [:]
    public init() {}
    public func secret(for key: String) -> String? { values[key] }
    public func setSecret(_ value: String?, for key: String) throws { values[key] = value }
}
