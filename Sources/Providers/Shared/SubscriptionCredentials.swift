import Foundation
import Security
import LocalAuthentication

enum SubscriptionCredentials {
    static let service = "local.burndownbar"
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static func saved(_ account: String) -> String? {
        read(account, service: service)
    }
    private static func read(_ account: String, service: String) -> String? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func preferCookies(_ origin: AccountOrigin) -> Bool {
        UserDefaults.standard.string(forKey: "authMode-\(origin.rawValue)") != "key"
    }
    static func save(_ value: String, account: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SubscriptionError.message("Enter a credential before saving.") }
        guard !value.contains("\n"), !value.contains("\r"), !value.contains("\0") else {
            throw SubscriptionError.message("Enter the credential on a single line.")
        }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var new = query.merging(attributes, uniquingKeysWith: { _, new in new })
            new[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(new as CFDictionary, nil) == errSecSuccess else {
                throw SubscriptionError.message("macOS could not save this credential in Keychain.")
            }
        } else if result != errSecSuccess { throw SubscriptionError.message("macOS could not update this Keychain credential.") }
    }
    static func json(_ relativePath: String) -> Any? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(relativePath)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    static func jwt(_ token: String) -> JSON? {
        let pieces = token.components(separatedBy: ".")
        guard pieces.count >= 2 else { return nil }
        var payload = pieces[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? JSON
    }
}
