import Foundation
import Security

enum Keychain {
    private static let service = "dev.onecap.provider-keys"
    static func save(_ key: String, for id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        let data = Data(key.utf8)
        let status = SecItemUpdate(
            query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else {
                throw AppFailure("Keychain could not save the key (\(added)).")
            }
        } else if status != errSecSuccess {
            throw AppFailure("Keychain could not update the key (\(status)).")
        }
    }
    static func read(_ id: UUID) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
                else {
            throw AppFailure("No API key is available for this provider. Save it again in Providers.")
        }
        return key
    }
    static func delete(_ id: UUID) throws {
        let status = SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString,
            ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppFailure("Could not remove the API key (\(status)).")
        }
    }
}
