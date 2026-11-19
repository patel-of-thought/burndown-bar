import Foundation

extension QuotaParser {
    /// Applies a Codex `wham/usage` body to an account, whether it was fetched directly or through the proxy.
    static func applyCodex(_ body: JSON, to account: inout Account) {
        account.windows = codex(body)
        account.plan = string(body["plan_type"])?.capitalized ?? account.plan
        if let credits = body["credits"] as? JSON {
            if credits["unlimited"] as? Bool == true { account.credits = "Unlimited" }
            else if let balance = number(credits["balance"]) {
                account.credits = balance.formatted(.number.precision(.fractionLength(0...2)))
            }
        }
    }

    static func codex(_ data: JSON, now: Date = Date()) -> [QuotaWindow] {
        var result: [QuotaWindow] = []
        for (key, prefix) in [("rate_limit", ""), ("code_review_rate_limit", "review-")] {
            guard let limits = data[key] as? JSON else { continue }
            for (field, defaultTitle, defaultPeriod) in [("primary_window", "5-hour", 18000.0), ("secondary_window", "Weekly", 604800.0)] {
                guard let window = limits[field] as? JSON else { continue }
                let period = number(window["limit_window_seconds"]) ?? defaultPeriod
                let title = period >= 2419200 ? "Monthly" : period == 604800 ? "Weekly" : period == 18000 ? "5-hour" : defaultTitle
                let used = number(window["used_percent"])
                let reset = date(window["reset_at"]) ?? number(window["reset_after_seconds"]).map { now.addingTimeInterval($0) }
                result.append(QuotaWindow(id: prefix + field,
                    title: prefix.isEmpty ? title : "Code review · \(title.lowercased())",
                    remaining: used.map { max(0, min(100, 100 - $0)) }, reset: reset, period: period))
            }
        }
        return result
    }
}
