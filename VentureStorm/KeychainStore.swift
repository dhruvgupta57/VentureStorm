import Foundation
import Security

/// Saves the Groq API key in the iPhone's Keychain, so it is never stored in the code.
enum KeychainStore {
    private static let service = "VentureStorm"
    private static let account = "groqAPIKey"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The key the app uses: the one in Secrets.swift if set, otherwise the one saved in Settings.
    static func currentKey() -> String? {
        let codeKey = Secrets.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return codeKey.isEmpty ? readKey() : codeKey
    }

    static var keyIsInCode: Bool {
        !Secrets.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func readKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    static func saveKey(_ key: String) {
        deleteKey()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var query = baseQuery
        query[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
