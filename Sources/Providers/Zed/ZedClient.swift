import Foundation

extension SubscriptionClient {
    func fetchZed(key suppliedKey: String?, cookie suppliedCookie: String?, zedAuthorization: String?) async throws -> (account: Account, source: String) {
        var account: Account
        var source = "Browser sign-in"
        if let cookie = suppliedCookie ?? (zedAuthorization == nil ? SubscriptionCredentials.cookie(.zed) : nil) {
            account = try AdditionalParsers.zed(await request(url: "https://cloud.zed.dev/frontend/billing/usage", provider: "Zed", headers: ["Cookie": cookie]), web: true)
        } else if let auth = zedAuthorization ?? suppliedKey ?? (SubscriptionCredentials.preferCookies(.zed) ? nil : SubscriptionCredentials.providerKey(.zed)) {
            account = try AdditionalParsers.zed(await request(url: "https://cloud.zed.dev/client/users/me", provider: "Zed", headers: ["Authorization": auth]))
            source = "Saved Zed credential"
        } else { throw SubscriptionError.message("Open Zed in your default browser, then paste its Cookie header in Connections and choose Save & connect.") }
        return (account, source)
    }
}
