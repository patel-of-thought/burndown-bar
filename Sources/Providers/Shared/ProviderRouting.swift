import Foundation

extension SubscriptionClient {
    func additional(_ origin: AccountOrigin, key suppliedKey: String? = nil, standardKey suppliedStandardKey: String? = nil, cookie suppliedCookie: String? = nil, zedAuthorization: String? = nil, workspaceID: String? = nil, codex suppliedCodex: SubscriptionCredentials.CodexSession? = nil) async throws -> Account {
        var account: Account
        var source = "Browser sign-in"
        switch origin {
        case .copilot:
            (account, source) = try await fetchCopilot(key: suppliedKey)
        case .warp:
            (account, source) = try await fetchWarp(key: suppliedKey, cookie: suppliedCookie)
        case .zed:
            (account, source) = try await fetchZed(key: suppliedKey, cookie: suppliedCookie, zedAuthorization: zedAuthorization)
        case .opencode:
            (account, source) = try await fetchOpenCode(key: suppliedKey, cookie: suppliedCookie, workspaceID: workspaceID)
        case .codex:
            (account, source) = try await fetchCodex(credentials: suppliedCodex)
        case .antigravity:
            return try await AntigravityLocalClient().fetch()
        case .claude:
            (account, source) = try await fetchClaude(cookie: suppliedCookie)
        case .grok:
            (account, source) = try await fetchGrok(key: suppliedKey)
        case .openrouter:
            (account, source) = try await fetchOpenRouter(key: suppliedKey, standardKey: suppliedStandardKey)
        default: throw SubscriptionError.message("This connection type is not supported.")
        }
        account.updatedAt = Date(); account.error = nil
        var details = account.details ?? ProviderDetails(source: source)
        details.source = source; details.dashboardURL = URL(string: origin.dashboard)
        let app = origin == .warp ? "Warp" : origin == .zed ? "Zed" : nil
        details.version = app.flatMap { Self.appVersion("/Applications/\($0).app") }
        account.details = details
        return account
    }

    static func safeID(_ value: String) -> Bool {
        !value.isEmpty && value.count < 200 && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0) }
    }
}
