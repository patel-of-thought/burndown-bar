import Foundation

extension SubscriptionParser {
    static func factory(limits: JSON, now: Date = Date()) throws -> [QuotaWindow] {
        guard limits["usesTokenRateLimitsBilling"] as? Bool == true,
              let pools = limits["limits"] as? JSON, let standard = pools["standard"] as? JSON else {
            throw SubscriptionError.message("This Factory plan did not return rate-limit windows.")
        }
        var result = factoryPool(standard, prefix: "", now: now)
        if let core = pools["core"] as? JSON {
            let coreWindows = factoryPool(core, prefix: "Core ", now: now)
            if coreWindows.contains(where: { ($0.remaining ?? 100) < 100 || $0.reset != nil }) {
                result += coreWindows
            }
        }
        guard !result.isEmpty else { throw SubscriptionError.message("Factory did not return any quota windows.") }
        return result
    }

    private static func factoryPool(_ pool: JSON, prefix: String, now: Date) -> [QuotaWindow] {
        [("fiveHour", "5-hour", 18000.0), ("weekly", "Weekly", 604800.0), ("monthly", "Monthly", 2592000.0)].compactMap { key, title, period in
            guard let raw = pool[key] as? JSON else { return nil }
            let end = date(raw["windowEnd"])
            let seconds = number(raw["secondsRemaining"])
            let reset = seconds.flatMap { $0 > 0 ? now.addingTimeInterval($0) : nil } ?? end.flatMap { $0 > now ? $0 : nil }
            var used = number(raw["usedPercent"])
            // Factory's UI treats an expired, explicitly dated rolling window as reset.
            if let end, end <= now, seconds == nil, used != nil { used = 0 }
            return QuotaWindow(id: "factory-\(prefix)\(key)", title: prefix + title,
                               remaining: used.map { max(0, min(100, 100 - $0)) }, reset: reset, period: period)
        }
    }

    static func factoryPlan(_ auth: JSON, limits: JSON) -> String {
        let org = auth["organization"] as? JSON ?? [:]
        let sub = org["subscription"] as? JSON ?? [:]
        let orb = sub["orbSubscription"] as? JSON ?? [:]
        let plan = orb["plan"] as? JSON ?? [:]
        var parts = [String]()
        if let tier = string(sub["factoryTier"]) { parts.append("Factory \(tier.capitalized)") }
        if let name = string(plan["name"]), !name.lowercased().contains("factory") { parts.append(name) }
        if let fallback = string(limits["overagePreference"]) { parts.append("Fallback: \(fallback)") }
        return parts.isEmpty ? "Factory subscription" : parts.joined(separator: " – ")
    }
}
