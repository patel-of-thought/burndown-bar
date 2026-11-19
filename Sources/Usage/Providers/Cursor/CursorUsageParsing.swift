import Foundation

extension SubscriptionParser {
    static func cursor(summary: JSON, sand: JSON?, now: Date = Date()) -> [QuotaWindow] {
        let start = date(summary["billingCycleStart"])
        let end = date(summary["billingCycleEnd"])
        let period = start.flatMap { start in end.flatMap { $0 > start ? $0.timeIntervalSince(start) : nil } }
        let individual = summary["individualUsage"] as? JSON ?? [:]
        let plan = individual["plan"] as? JSON ?? [:]
        let auto = number(plan["autoPercentUsed"])
        let api = number(plan["apiPercentUsed"])
        var total = number(plan["totalPercentUsed"])
        if total == nil, let auto, let api { total = (auto + api) / 2 }
        if total == nil { total = api ?? auto }
        if total == nil {
            let team = summary["teamUsage"] as? JSON ?? [:]
            for bucket in [plan, individual["overall"] as? JSON ?? [:], team["pooled"] as? JSON ?? [:]] {
                if let used = number(bucket["used"]), let limit = number(bucket["limit"]), limit > 0 {
                    total = used / limit * 100; break
                }
            }
        }
        func window(_ id: String, _ title: String, _ used: Double?, reset: Date?, period: Double?) -> QuotaWindow {
            QuotaWindow(id: id, title: title, remaining: used.map { max(0, min(100, 100 - $0)) }, reset: reset, period: period)
        }
        var grok: QuotaWindow?
        if let sand, let used = number(sand["usagePercent"]) {
            let included = (sand["includedLimitZero"] as? Bool).map { !$0 } ?? sand["hasNonZeroIncludedLimit"] as? Bool
            let trial = date(sand["sandTrialExpiresAt"]).map { $0 > now } ?? false
            if included == true || trial {
                let reset = included == true ? date(sand["nextResetTimestampUtc"]) : nil
                grok = window("cursor-grok-bot", "Grok Bot", used, reset: reset, period: reset == nil ? nil : 604800)
            }
        }
        if sand?["isUnified"] as? Bool == true, let grok, let reset = grok.reset, reset > now {
            return [QuotaWindow(id: "cursor-unified", title: "Weekly", remaining: grok.remaining, reset: reset, period: 604800)]
        }
        var windows = [window("cursor-total", "Total", total, reset: end, period: period)]
        if let auto { windows.append(window("cursor-auto", "Cursor", auto, reset: end, period: period)) }
        if let api { windows.append(window("cursor-api", "Third Party", api, reset: end, period: period)) }
        if let grok { windows.append(grok) }
        return windows
    }

    static func costs(events: [JSON], now: Date = Date(), calendar: Calendar = .current) -> UsageCosts {
        let today = calendar.startOfDay(for: now)
        let since = calendar.date(byAdding: .day, value: -29, to: today)!
        var todayCost = 0.0, monthCost = 0.0
        var todayTokens: Int64 = 0, monthTokens: Int64 = 0
        var todayCostKnown = 0, monthCostKnown = 0, todayTokenKnown = 0, monthTokenKnown = 0
        var todayCount = 0, monthCount = 0, invalidDate = false
        var byDay = [Date: DailyUsage]()
        for event in events {
            guard let timestamp = date(event["timestamp"]) else { invalidDate = true; continue }
            guard timestamp >= since, timestamp <= now else { continue }
            monthCount += 1
            let isToday = timestamp >= today
            let day = calendar.startOfDay(for: timestamp)
            if isToday { todayCount += 1 }
            guard let usage = event["tokenUsage"] as? JSON else { continue }
            if let cents = number(usage["totalCents"]), cents >= 0 {
                monthCost += cents / 100; monthCostKnown += 1
                if isToday { todayCost += cents / 100; todayCostKnown += 1 }
                byDay[day, default: DailyUsage(date: day)].dollars += cents / 100
            }
            let fields = ["inputTokens", "outputTokens", "cacheWriteTokens", "cacheReadTokens"]
            let present = fields.filter { usage[$0] != nil }
            let values = fields.map { number(usage[$0]) ?? (usage[$0] == nil ? 0 : -1) }
            guard !present.isEmpty, values.allSatisfy({ $0 >= 0 && $0 < Double(Int64.max) && $0.rounded(.towardZero) == $0 }) else { continue }
            let total = values.reduce(0, +)
            guard total < Double(Int64.max) else { continue }
            let (nextMonth, overflow) = monthTokens.addingReportingOverflow(Int64(total))
            guard !overflow else { continue }
            monthTokens = nextMonth; monthTokenKnown += 1
            func count(_ key: String) -> Int64 { Int64(number(usage[key]) ?? 0) }
            byDay[day, default: DailyUsage(date: day)].input &+= count("inputTokens")
            byDay[day, default: DailyUsage(date: day)].output &+= count("outputTokens")
            byDay[day, default: DailyUsage(date: day)].cacheRead &+= count("cacheReadTokens")
            byDay[day, default: DailyUsage(date: day)].cacheWrite &+= count("cacheWriteTokens")
            if isToday {
                let (next, overflow) = todayTokens.addingReportingOverflow(Int64(total))
                if !overflow { todayTokens = next; todayTokenKnown += 1 }
            }
        }
        let todayComplete = !invalidDate && todayCostKnown == todayCount && todayTokenKnown == todayCount
        let monthComplete = !invalidDate && monthCostKnown == monthCount && monthTokenKnown == monthCount
        let daily = (0..<30).compactMap { offset -> DailyUsage? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: since) else { return nil }
            return byDay[day] ?? DailyUsage(date: day)
        }
        return UsageCosts(
            today: CostPeriod(dollars: (todayCount == 0 && !invalidDate) || todayCostKnown > 0 ? todayCost : nil,
                              tokens: (todayCount == 0 && !invalidDate) || todayTokenKnown > 0 ? todayTokens : nil, isComplete: todayComplete),
            last30Days: CostPeriod(dollars: (monthCount == 0 && !invalidDate) || monthCostKnown > 0 ? monthCost : nil,
                                   tokens: (monthCount == 0 && !invalidDate) || monthTokenKnown > 0 ? monthTokens : nil, isComplete: monthComplete),
            updatedAt: now,
            warning: monthComplete ? nil : "Some events lack valid cost or token data. Totals are partial.",
            daily: daily)
    }
}
