import Foundation

extension SubscriptionCredentials {
    struct FactorySession { let token: String; let source: String }
    static func factory() throws -> FactorySession {
        if let key = saved("factory-key") { return FactorySession(token: key, source: "API key · Keychain") }
        if let key = ProcessInfo.processInfo.environment["FACTORY_API_KEY"], !key.isEmpty { return FactorySession(token: key, source: "API key · environment") }
        if let text = try? String(contentsOf: home.appendingPathComponent(".factory/.env"), encoding: .utf8) {
            for line in text.components(separatedBy: .newlines) {
                let line = line.trimmingCharacters(in: .whitespaces)
                let normalized = line.hasPrefix("export ") ? String(line.dropFirst(7)) : line
                guard normalized.hasPrefix("FACTORY_API_KEY="), let eq = normalized.firstIndex(of: "=") else { continue }
                let key = normalized[normalized.index(after: eq)...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
                if !key.isEmpty { return FactorySession(token: key, source: "API key · Factory environment file") }
            }
        }
        throw SubscriptionError.message("Add your Factory API key in Settings to connect Droid usage.")
    }
}
