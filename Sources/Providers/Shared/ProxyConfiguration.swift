import Foundation

struct ProxyConfiguration {
    let port: Int
    let secret: String
    var endpoint: String { "127.0.0.1:\(port)" }

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.cpa.gui/config.toml")
    }
    static func load() throws -> ProxyConfiguration {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw ProxyError.message("Open CLIProxyAPI and start its proxy to connect.")
        }
        return try parse(text)
    }
    static func parse(_ text: String) throws -> ProxyConfiguration {
        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break } // Only root configuration keys.
            guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), let data = value.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String {
                values[key] = decoded
            } else if value.hasPrefix("'"), value.hasSuffix("'") {
                values[key] = String(value.dropFirst().dropLast())
            } else { values[key] = value.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces) }
        }
        guard let secret = values["management-secret-key"], !secret.isEmpty else {
            throw ProxyError.message("Set a management key in CLIProxyAPI to connect.")
        }
        let port = Int(values["port"] ?? "8317") ?? 8317
        guard (1...65535).contains(port) else { throw ProxyError.message("The proxy port is invalid.") }
        return ProxyConfiguration(port: port, secret: secret)
    }
}

enum ProxyError: LocalizedError {
    case message(String)
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .message(let s): return s
        case .http(401), .http(403): return "Access denied. Check the account in CLIProxyAPI."
        case .http(429): return "Too many refreshes. Wait a moment and try again."
        case .http(let code): return "The proxy returned HTTP \(code)."
        }
    }
}
