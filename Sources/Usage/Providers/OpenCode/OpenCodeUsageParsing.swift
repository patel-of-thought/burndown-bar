import Foundation

extension AdditionalParsers {
    static func openCode(_ raw: JSON, console: Bool = false, now: Date = Date()) throws -> Account {
        var account = SubscriptionClient.placeholder(.opencode)
        let access = raw["access"] as? JSON ?? [:]
        let usage = console ? access["meters"] as? JSON ?? [:] : raw["usage"] as? JSON ?? [:]
        guard !usage.isEmpty else { throw SubscriptionError.message("OpenCode did not return subscription usage. Use a Go key or connect a Console session.") }
        for (key, title, seconds) in [(console ? "fiveHour" : "rolling", "5-hour", 18000.0), (console ? "week" : "weekly", "Weekly", 604800.0), (console ? "month" : "monthly", "Monthly", 2592000.0)] {
            guard let meter = usage[key] as? JSON else { continue }
            let direct = firstNumber(meter, keys: ["usagePercent", "usedPercent", "percentUsed", "percent", "usage_percent", "used_percent", "utilization", "utilizationPercent", "utilization_percent", "usage"])
            var used = direct
            if console, let value = used, value >= 0 && value <= 1 { used = value * 100 }
            if used == nil, let count = firstNumber(meter, keys: ["used", "consumed", "count", "usedTokens", "usedMicroCents"]),
               let limit = firstNumber(meter, keys: ["limit", "total", "quota", "cap", "tokenLimit", "limitMicroCents"]), limit > 0 { used = count / limit * 100 }
            let relative = firstNumber(meter, keys: ["resetInSec", "resetInSeconds", "resetSeconds", "reset_sec", "reset_in_sec", "resetsInSec", "resetsInSeconds", "resetIn", "resetSec"])
            let reset = firstDate(meter, keys: ["resetAt", "resetsAt", "reset_at", "resets_at", "nextReset", "next_reset", "renewAt", "renew_at"])
                ?? relative.flatMap { $0 >= 0 ? now.addingTimeInterval($0) : nil }
                ?? (title == "Monthly" ? date(access["endsAt"] ?? raw["renewAt"]) : nil)
            account.windows.append(QuotaWindow(id: "opencode-\(key)", title: title, remaining: used.map { max(0, min(100, 100 - $0)) }, reset: reset, period: seconds))
        }
        guard !account.windows.isEmpty else { throw SubscriptionError.message("OpenCode did not return recognized quota windows.") }
        account.plan = string(raw["plan"] ?? access["plan"]) ?? "OpenCode Go"
        account.updatedAt = now
        return account
    }
}
