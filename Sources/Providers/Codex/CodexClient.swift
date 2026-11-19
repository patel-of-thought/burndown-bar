import Foundation

extension SubscriptionClient {
    func fetchCodex(credentials suppliedCodex: SubscriptionCredentials.CodexSession?) async throws -> (account: Account, source: String) {
        var account: Account
        let session = try suppliedCodex ?? SubscriptionCredentials.codex()
        var headers = ["Authorization": "Bearer \(session.token)", "User-Agent": Self.codexUserAgent]
        if let id = session.accountID { headers["Chatgpt-Account-Id"] = id }
        let raw = try await request(url: "https://chatgpt.com/backend-api/wham/usage", provider: "Codex", headers: headers)
        account = Self.placeholder(.codex)
        QuotaParser.applyCodex(raw, to: &account)
        guard !account.windows.isEmpty else { throw SubscriptionError.message("Codex did not return quota windows for this account.") }
        account = AdditionalParsers.withIdentity(account, email: session.email)
        return (account, session.source)
    }

    static let codexUserAgent = "codex-tui/0.149.1 (Mac OS; arm64)"
}
