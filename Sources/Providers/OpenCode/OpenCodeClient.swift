import Foundation

extension SubscriptionClient {
    func fetchOpenCode(key suppliedKey: String?, cookie suppliedCookie: String?, workspaceID: String?) async throws -> (account: Account, source: String) {
        var account: Account
        var source = "Browser sign-in"
        if let cookie = suppliedCookie ?? (suppliedKey == nil ? SubscriptionCredentials.cookie(.opencode) : nil) {
            account = try await openCodeConsole(cookie: cookie, workspaceID: workspaceID)
        } else if let key = suppliedKey ?? SubscriptionCredentials.providerKey(.opencode) {
            account = try AdditionalParsers.openCode(await request(url: "https://opencode.ai/zen/go/v1/usage", provider: "OpenCode", headers: ["Authorization": "Bearer \(key)"]))
            source = "OpenCode Go API key"
        } else { throw SubscriptionError.message("Sign into OpenCode in Connections, or enter your Go API key.") }
        return (account, source)
    }

    private func openCodeConsole(cookie: String, workspaceID: String?) async throws -> Account {
        var headers = ["Cookie": cookie, "Origin": "https://opencode.ai"]
        let value = try await requestValue(url: "https://opencode.ai/console/api/orgs", provider: "OpenCode", headers: headers)
        let orgs = value as? [JSON] ?? (value as? JSON)?["orgs"] as? [JSON] ?? (value as? JSON)?["organizations"] as? [JSON] ?? []
        let preferred = (workspaceID ?? UserDefaults.standard.string(forKey: "opencodeWorkspace") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = orgs.compactMap { string($0["id"] ?? $0["orgId"]) }
        if !preferred.isEmpty, !Self.safeID(preferred) || !ids.contains(preferred) {
            throw SubscriptionError.message("That OpenCode workspace is invalid or is not accessible to this account. Check the workspace ID in Connections.")
        }
        guard let id = preferred.isEmpty ? ids.first : preferred, Self.safeID(id) else { throw SubscriptionError.message("OpenCode has no accessible Console workspace.") }
        headers["x-org-id"] = id
        let raw = try await requestValue(url: "https://opencode.ai/console/api/go/status", provider: "OpenCode", headers: headers)
        var account: Account
        if let json = raw as? JSON, json["access"] is JSON { account = try AdditionalParsers.openCode(json, console: true) }
        else if raw is NSNull || (raw as? JSON)?["access"] is NSNull {
            let org = try await request(url: "https://opencode.ai/console/api/orgs/current", provider: "OpenCode", headers: headers)
            guard org["hasGoSubscription"] as? Bool == false else { throw SubscriptionError.message("The OpenCode subscription meters are unavailable for this workspace.") }
            let billing = try await request(url: "https://opencode.ai/console/api/billing/status", provider: "OpenCode", headers: headers)
            guard string(billing["mode"]) == "pay-as-you-go" else { throw SubscriptionError.message("This OpenCode workspace did not return a supported billing mode.") }
            let usage = try await request(url: "https://opencode.ai/console/api/usage/summary?range=30d", provider: "OpenCode", headers: headers)
            guard let amount = number(usage["totalCostMicroCents"]), amount >= 0 else { throw SubscriptionError.message("OpenCode returned an invalid cost summary.") }
            account = Self.placeholder(.opencode); account.plan = "OpenCode pay-as-you-go"
            account.facts.append(UsageFact(label: "Last 30 days", value: (amount / 100_000_000).formatted(.currency(code: "USD"))))
        } else { throw SubscriptionError.message("OpenCode did not return a recognized Console usage response.") }
        account.facts.append(UsageFact(label: "Workspace", value: id))
        if ids.count > 1 { account.facts.append(UsageFact(label: "Workspaces", value: "\(ids.count) available · set workspace ID in Connections")) }
        return account
    }
}
