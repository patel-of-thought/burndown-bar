import Foundation

extension AdditionalParsers {
    static func warp(_ raw: JSON, now: Date = Date()) throws -> Account {
        if let errors = raw["errors"] as? [Any], !errors.isEmpty { throw SubscriptionError.message("Warp rejected the usage query. Check your Warp API key.") }
        guard let data = raw["data"] as? JSON, let outer = data["user"] as? JSON, let user = outer["user"] as? JSON,
              let limits = user["requestLimitInfo"] as? JSON else { throw SubscriptionError.message("Warp did not return request limits.") }
        var account = SubscriptionClient.placeholder(.warp)
        let unlimited = limits["isUnlimited"] as? Bool == true
        if unlimited { account.facts.append(UsageFact(label: "AI credits", value: "Unlimited")) }
        else {
            let limit = number(limits["requestLimit"]), used = number(limits["requestsUsedSinceLastRefresh"])
            guard let limit, limit > 0, let used, used >= 0 else { throw SubscriptionError.message("Warp's AI credit counts are unavailable.") }
            account.windows.append(QuotaWindow(id: "warp-credits", title: "AI credits", remaining: max(0, min(100, (1 - used / limit) * 100)),
                                              reset: date(limits["nextRefreshTime"]), period: nil))
            account.facts.append(UsageFact(label: "Credits used", value: "\(used.formatted()) / \(limit.formatted())"))
        }
        var grants = user["bonusGrants"] as? [JSON] ?? []
        for workspace in user["workspaces"] as? [JSON] ?? [] {
            grants += (workspace["bonusGrantsInfo"] as? JSON)?["grants"] as? [JSON] ?? []
        }
        var total = 0.0, left = 0.0
        var expirations: [Date] = []
        for grant in grants {
            if let expiration = date(grant["expiration"]), expiration <= now { continue }
            guard let granted = number(grant["requestCreditsGranted"]), let remaining = number(grant["requestCreditsRemaining"]), granted >= 0, remaining >= 0 else { continue }
            total += granted; left += remaining
            if remaining > 0, let expiration = date(grant["expiration"]) { expirations.append(expiration) }
        }
        if total > 0 {
            // Bonus expiry is not a recurring reset, so it is shown separately.
            account.windows.append(QuotaWindow(id: "warp-bonus", title: "Bonus credits", remaining: max(0, min(100, left / total * 100)), reset: nil, period: nil))
            account.facts.append(UsageFact(label: "Bonus remaining", value: left.formatted()))
            if let expiration = expirations.min() { account.facts.append(UsageFact(label: "Next bonus expiry", value: expiration.formatted(date: .abbreviated, time: .shortened))) }
        }
        account.plan = unlimited ? "Unlimited" : "Warp"
        account.updatedAt = now
        return account
    }
}
