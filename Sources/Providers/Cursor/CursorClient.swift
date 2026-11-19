import Foundation

extension SubscriptionClient {
    func cursor(credentials supplied: SubscriptionCredentials.CursorSession? = nil, onQuota: ((Account) async -> Void)? = nil) async throws -> Account {
        let credentials: SubscriptionCredentials.CursorSession
        if let supplied { credentials = supplied }
        else { credentials = try await SubscriptionCredentials.cursor() }
        let headers = ["Cookie": credentials.cookie, "Origin": "https://cursor.com"]
        async let health = status("https://status.cursor.com/api/v2/status.json")
        async let profileRead = try? request(url: "https://cursor.com/api/auth/me", provider: "Cursor", headers: headers)
        async let sandRead = try? request(url: "https://cursor.com/api/dashboard/get-sand-usage-status", provider: "Cursor", headers: headers, body: [:])
        let summary = try await request(url: "https://cursor.com/api/usage-summary", provider: "Cursor", headers: headers)
        guard summary["individualUsage"] != nil || summary["teamUsage"] != nil || summary["membershipType"] != nil else {
            throw SubscriptionError.message("Cursor did not return a recognized usage summary.")
        }
        let (profile, sand, service) = await (profileRead, sandRead, health)
        let email = string(profile?["email"]) ?? credentials.email ?? "Cursor account"
        let identity = string(profile?["sub"]) ?? email
        var account = Self.placeholder(.cursor)
        account = Account(id: "direct-cursor", name: "Cursor", email: email, provider: "cursor", authIndex: "",
                          accountID: identity, disabled: false, plan: string(summary["membershipType"])?.capitalized ?? "Cursor subscription",
                          origin: .cursor)
        account.windows = SubscriptionParser.cursor(summary: summary, sand: sand)
        account.updatedAt = Date()
        let version = Self.appVersion("/Applications/Cursor.app")
        account.details = ProviderDetails(source: credentials.source, version: version, status: service?.description,
            statusIndicator: service?.indicator, warning: sand == nil ? "Grok Bot usage is currently unavailable." : nil,
            dashboardURL: URL(string: "https://cursor.com/dashboard?tab=usage"))
        await onQuota?(account)
        if let cached = cachedCosts, cached.identity == identity, Date().timeIntervalSince(cached.value.updatedAt) < 600 {
            account.costs = cached.value
        } else {
            do {
                let costs = try await cursorCosts(headers: headers)
                cachedCosts = (identity, costs)
                account.costs = costs
            } catch {
                if let cached = cachedCosts, cached.identity == identity {
                    var costs = cached.value
                    costs.warning = "Showing previous costs. \(Self.message(error, provider: "Cursor"))"
                    account.costs = costs
                } else {
                    account.costs = UsageCosts(today: CostPeriod(dollars: nil, tokens: nil), last30Days: CostPeriod(dollars: nil, tokens: nil),
                                              updatedAt: Date(), warning: "Cost data unavailable. \(Self.message(error, provider: "Cursor"))")
                }
            }
        }
        return account
    }
}
