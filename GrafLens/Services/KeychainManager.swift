import Foundation
import Security

enum KeychainManager {

    static func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Convenience for strings
    static func saveString(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }

    static func loadString(forKey key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Connection-specific key storage
    static func saveAPIKey(_ apiKey: String, forConnectionID id: UUID) {
        _ = saveString(apiKey, forKey: "graflens.apikey.\(id.uuidString)")
    }

    static func loadAPIKey(forConnectionID id: UUID) -> String? {
        return loadString(forKey: "graflens.apikey.\(id.uuidString)")
    }

    static func deleteAPIKey(forConnectionID id: UUID) {
        delete(key: "graflens.apikey.\(id.uuidString)")
    }
}
