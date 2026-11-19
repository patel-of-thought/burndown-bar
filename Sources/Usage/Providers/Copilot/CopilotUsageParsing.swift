import Foundation

extension AdditionalParsers {
    static func copilot(_ raw: JSON, now: Date = Date()) throws -> Account {
        if string(raw["access_type_sku"]) == "subscription_ended" { throw SubscriptionError.message("Your Copilot subscription has ended.") }
        guard raw["quota_snapshots"] != nil || raw["monthly_quotas"] != nil || raw["token_based_billing"] != nil else {
            throw SubscriptionError.message("GitHub did not return a recognized Copilot quota response.")
        }
        var account = SubscriptionClient.placeholder(.copilot)
        account.plan = string(raw["copilot_plan"])?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Copilot"
        let resetString = string(raw["quota_reset_date_utc"] ?? raw["quota_reset_date"])
        let reset = resetString.flatMap { date($0) ?? date($0 + "T00:00:00Z") }
        let snapshots = raw["quota_snapshots"] as? JSON ?? [:]
        let monthly = raw["monthly_quotas"] as? JSON ?? [:], remaining = raw["limited_user_quotas"] as? JSON ?? [:]
        for (key, title, legacy) in [("premium_interactions", "Premium", "completions"), ("chat", "Chat", "chat"), ("completions", "Completions", "completions")] {
            if key == "completions", snapshots[key] == nil { continue }
            let snapshot = snapshots[key] as? JSON ?? [:]
            let unlimited = snapshot["unlimited"] as? Bool == true
            if let credits = number(snapshot["credits_used"]) {
                account.facts.append(UsageFact(label: "\(title) credits used", value: credits.formatted()))
            }
            let placeholder = number(snapshot["entitlement"]) == 0 && number(snapshot["remaining"]) == 0
            var percent = unlimited || placeholder ? nil : number(snapshot["percent_remaining"])
            if percent == nil, !unlimited, !placeholder, let limit = number(snapshot["entitlement"]), limit > 0, let left = number(snapshot["remaining"]) {
                percent = left / limit * 100
            }
            if percent == nil, let limit = number(monthly[legacy]), limit > 0, let left = number(remaining[legacy]) { percent = left / limit * 100 }
            if let percent {
                account.windows.append(QuotaWindow(id: "copilot-\(key)", title: title, remaining: min(100, max(0, percent)), reset: reset, period: nil))
            } else if unlimited { account.facts.append(UsageFact(label: title, value: "Unlimited")) }
        }
        if raw["token_based_billing"] as? Bool == true {
            account.facts.append(UsageFact(label: "Billing", value: "Token-based · quota ceiling not reported"))
        }
        guard !account.windows.isEmpty || !account.facts.isEmpty else { throw SubscriptionError.message("Copilot did not report usable quota data for this seat.") }
        account.updatedAt = now
        return account
    }
}
