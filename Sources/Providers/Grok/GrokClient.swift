import Foundation

extension SubscriptionClient {
    func fetchGrok(key suppliedKey: String?) async throws -> (account: Account, source: String) {
        var account: Account
        guard let token = suppliedKey ?? SubscriptionCredentials.providerKey(.grok) else {
            throw SubscriptionError.message("Grok billing requires a Grok CLI access token. Cookie-only billing is no longer accepted; sign in with the Grok CLI and enter its token in Connections.")
        }
        let headers = ["Authorization": "Bearer \(token)", "x-xai-token-auth": "xai-grok-cli", "x-grok-client-version": "1.0.70", "User-Agent": "grok-pager/1.0.70 grok-shell/1.0.70 (macos; aarch64)"]
        let raw = try await request(url: "https://cli-chat-proxy.grok.com/v1/billing?format=credits", provider: "Grok", headers: headers)
        account = try AdditionalParsers.grok(raw)
        return (account, "Grok CLI sign-in token")
    }
}
