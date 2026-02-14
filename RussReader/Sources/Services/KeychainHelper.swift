import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.russreader.feedAuth"
    
    struct BasicAuthCredentials: Codable {
        let username: String
        let password: String
    }
    
    struct TokenCredentials: Codable {
        let token: String
    }
    
    static func saveBasicAuth(feedId: UUID, username: String, password: String) {
        let creds = BasicAuthCredentials(username: username, password: password)
        guard let data = try? JSONEncoder().encode(creds) else { return }
        save(account: feedId.uuidString, data: data)
    }
    
    static func saveToken(feedId: UUID, token: String) {
        let creds = TokenCredentials(token: token)
        guard let data = try? JSONEncoder().encode(creds) else { return }
        save(account: feedId.uuidString, data: data)
    }
    
    static func loadBasicAuth(feedId: UUID) -> BasicAuthCredentials? {
        guard let data = load(account: feedId.uuidString) else { return nil }
        return try? JSONDecoder().decode(BasicAuthCredentials.self, from: data)
    }
    
    static func loadToken(feedId: UUID) -> TokenCredentials? {
        guard let data = load(account: feedId.uuidString) else { return nil }
        return try? JSONDecoder().decode(TokenCredentials.self, from: data)
    }
    
    static func deleteCredentials(feedId: UUID) {
        delete(account: feedId.uuidString)
    }
    
    // MARK: - Private Keychain Operations
    
    private static func save(account: String, data: Data) {
        // Delete existing item first
        delete(account: account)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // Try update instead if item somehow still exists
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemUpdate(updateQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }
    
    private static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
