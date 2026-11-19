import Foundation

extension SubscriptionCredentials {
    /// Environment variable names, in lookup order, for each provider's API key or access token.
    static let keyVariables: [AccountOrigin: [String]] = [
        .factory: ["FACTORY_API_KEY"],
        .codex: ["CODEX_ACCESS_TOKEN"],
        .opencode: ["OPENCODE_GO_API_KEY", "OPENCODE_API_KEY"],
        .warp: ["WARP_API_KEY", "WARP_TOKEN"],
        .zed: ["ZED_AUTHORIZATION"],
        .copilot: ["COPILOT_GITHUB_TOKEN"],
        .grok: ["GROK_ACCESS_TOKEN"],
        .openrouter: ["OPENROUTER_MANAGEMENT_KEY", "OPENROUTER_API_KEY"],
    ]

    /// Order: Keychain (saved in this app), then process environment variables.
    static func providerKey(_ origin: AccountOrigin) -> String? {
        if let key = saved("\(origin.rawValue)-key") { return key }
        for name in keyVariables[origin] ?? [] {
            if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty { return value }
        }
        return nil
    }
    static func namedKey(account: String, variable: String) -> String? {
        if let key = saved(account) { return key }
        if let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty { return value }
        return nil
    }
    static func cookie(_ origin: AccountOrigin) -> String? {
        guard preferCookies(origin) else { return nil }
        return saved("\(origin.rawValue)-cookie")
    }
}

enum ProviderCookiePolicy {
    static func domains(_ origin: AccountOrigin) -> [String] {
        switch origin {
        case .cursor: return ["cursor.com"]
        case .factory: return ["factory.ai"]
        case .opencode: return ["opencode.ai"]
        case .zed: return ["zed.dev"]
        case .warp: return ["warp.dev"]
        case .claude: return ["claude.ai"]
        case .grok: return ["grok.com"]
        default: return []
        }
    }
    static func header(_ cookies: [HTTPCookie], origin: AccountOrigin, now: Date = Date()) -> String? {
        let domains = domains(origin)
        let accepted = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domains.contains(where: { domain == $0 || domain.hasSuffix("." + $0) })
                && (cookie.expiresDate.map { $0 > now } ?? true)
                && !cookie.name.contains(where: { $0.isNewline }) && !cookie.value.contains(where: { $0.isNewline })
        }
        guard !accepted.isEmpty else { return nil }
        return accepted.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}
