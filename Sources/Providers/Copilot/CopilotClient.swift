import Foundation

extension SubscriptionClient {
    func fetchCopilot(key suppliedKey: String?) async throws -> (account: Account, source: String) {
        var account: Account
        guard let token = suppliedKey ?? SubscriptionCredentials.providerKey(.copilot) else { throw SubscriptionError.message("Choose Sign in with GitHub to connect Copilot.") }
        let headers = Self.copilotHeaders(token)
        let raw = try await request(url: "https://api.github.com/copilot_internal/user", provider: "Copilot", headers: headers)
        account = try AdditionalParsers.copilot(raw)
        if let user = try? await request(url: "https://api.github.com/user", provider: "Copilot", headers: headers) {
            let original = account
            account = AdditionalParsers.withIdentity(account, email: string(user["login"]))
            account.windows = original.windows; account.facts = original.facts; account.updatedAt = original.updatedAt
        }
        return (account, "GitHub sign-in")
    }

    static func copilotHeaders(_ token: String) -> [String: String] {
        ["Authorization": "token \(token)", "Editor-Version": "vscode/1.96.2", "Editor-Plugin-Version": "copilot-chat/0.26.7",
         "User-Agent": "GitHubCopilotChat/0.26.7", "X-Github-Api-Version": "2025-04-01"]
    }
}
