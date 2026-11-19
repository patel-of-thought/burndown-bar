import Foundation

extension SubscriptionClient {
    func fetchClaude(cookie suppliedCookie: String?) async throws -> (account: Account, source: String) {
        var account: Account
        guard let cookie = suppliedCookie ?? SubscriptionCredentials.cookie(.claude) else { throw SubscriptionError.message("Sign into Claude in Connections to read usage.") }
        let headers = ["Cookie": cookie, "Origin": "https://claude.ai"]
        guard let orgs = try await requestValue(url: "https://claude.ai/api/organizations", provider: "Claude", headers: headers) as? [JSON],
              let first = orgs.first, let id = string(first["uuid"]), Self.safeID(id) else { throw SubscriptionError.message("Claude did not return an organization for this account.") }
        let usage = try await request(url: "https://claude.ai/api/organizations/\(id)/usage", provider: "Claude", headers: headers)
        account = Self.placeholder(.claude)
        account.windows = QuotaParser.claude(usage)
        guard !account.windows.isEmpty else { throw SubscriptionError.message("Claude did not return subscription usage windows.") }
        account.plan = "Claude subscription"
        return (account, "Browser sign-in")
    }
}
