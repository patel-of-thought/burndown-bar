import Foundation

extension AdditionalParsers {
    static func zed(_ raw: JSON, web: Bool = false, now: Date = Date()) throws -> Account {
        let plan = raw["plan"] as? JSON ?? [:]
        guard let usage = (web ? raw["current_usage"] : plan["usage"]) as? JSON,
              let predictions = usage["edit_predictions"] as? JSON,
              let used = number(predictions["used"]), used >= 0 else { throw SubscriptionError.message("Zed did not return edit-prediction usage.") }
        var account = SubscriptionClient.placeholder(.zed)
        account.plan = (web ? string(raw["plan"]) : string(plan["plan_v3"]))?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Zed"
        let user = raw["user"] as? JSON ?? [:]
        account = withIdentity(account, email: string(user["github_login"]))
        let period = plan["subscription_period"] as? JSON ?? [:]
        let start = date(period["started_at"]), end = date(period["ended_at"])
        let duration = start.flatMap { start in end.flatMap { $0 > start ? $0.timeIntervalSince(start) : nil } }
        let limitValue = predictions["limit"]
        let unlimited = string(limitValue) == "unlimited" || (web && limitValue is NSNull)
        let limit = number((limitValue as? JSON)?["limited"] ?? limitValue)
        if unlimited { account.facts.append(UsageFact(label: "Edit predictions", value: "Unlimited · \(used.formatted()) used")) }
        else if let limit, limit > 0 {
            account.windows.append(QuotaWindow(id: "zed-predictions", title: "Edit predictions", remaining: max(0, min(100, (1 - used / limit) * 100)), reset: end, period: duration))
            account.facts.append(UsageFact(label: "Predictions used", value: "\(used.formatted()) / \(limit.formatted())"))
        } else { account.facts.append(UsageFact(label: "Edit predictions", value: "\(used.formatted()) used · limit unavailable")) }
        if let end { account.facts.append(UsageFact(label: "Billing cycle ends", value: end.formatted(date: .abbreviated, time: .shortened))) }
        if plan["has_overdue_invoices"] as? Bool == true { account.facts.append(UsageFact(label: "Billing", value: "Overdue invoices")) }
        if let spend = usage["token_spend"] as? JSON, let cents = number(spend["spend_in_cents"]), cents >= 0 {
            account.facts.append(UsageFact(label: "Token spend", value: (cents / 100).formatted(.currency(code: "USD"))))
            if let cap = number(spend["limit_in_cents"]), cap > 0 {
                account.windows.append(QuotaWindow(id: "zed-spend", title: "Token budget", remaining: max(0, min(100, (1 - cents / cap) * 100)), reset: end, period: duration))
            }
        }
        account.updatedAt = now
        return account
    }
}
