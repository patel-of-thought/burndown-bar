import Foundation

struct QuotaWindow: Identifiable {
    let id: String
    let title: String
    let remaining: Double?
    let reset: Date?
    let period: TimeInterval?

    var percent: String { remaining.map { "\(Int($0.rounded()))%" } ?? "—" }
    func resetLabel(now: Date) -> String {
        guard let reset else { return "Reset time unavailable" }
        return reset <= now ? "Reset due · refresh to update" : "Resets in \(duration(reset.timeIntervalSince(now)))"
    }
    func pace(now: Date) -> (text: String, healthy: Bool)? {
        guard let remaining, let reset, let period, period > 0,
              reset > now, reset.timeIntervalSince(now) <= period else { return nil }
        let expected = min(100, reset.timeIntervalSince(now) / period * 100)
        let reserve = remaining - expected
        return reserve >= 0
            ? ("\(Int(reserve.rounded()))% in reserve · Lasts until reset", true)
            : ("\(Int(abs(reserve).rounded()))% ahead of a steady pace", false)
    }
}

/// Where a proxy-capable provider's quota is read from.
enum QuotaSource: String, CaseIterable, Identifiable {
    case proxy, direct
    var id: String { rawValue }
    var title: String { self == .proxy ? "CLIProxyAPI" : "Direct" }
}

struct UsageFact: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

struct CostPeriod {
    var dollars: Double?
    var tokens: Int64?
    var isComplete: Bool = true
    var label: String {
        var parts: [String] = []
        if let dollars { parts.append(dollars.formatted(.currency(code: "USD"))) }
        if let tokens {
            parts.append("\(compactCount(tokens)) tokens")
        }
        return parts.isEmpty ? "Unavailable" : parts.joined(separator: " · ") + (isComplete ? "" : " · partial")
    }
}

struct DailyUsage: Identifiable {
    var date: Date
    var dollars = 0.0
    var input: Int64 = 0
    var output: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheWrite: Int64 = 0
    var id: Date { date }
    var tokens: Int64 { input + output + cacheRead + cacheWrite }
}

struct UsageCosts {
    var today: CostPeriod
    var last30Days: CostPeriod
    var updatedAt: Date
    var warning: String?
    /// One entry per calendar day, oldest first, including days with no usage.
    var daily: [DailyUsage] = []
}

/// One source of daily usage for an account, e.g. Cursor's usage events or CLIProxyAPI's request log.
struct UsageSeries: Identifiable {
    let id: String
    let title: String
    var daily: [DailyUsage]
    /// Dollar amounts are only present when the source reports them.
    var hasCost: Bool
    var hasData: Bool { daily.contains { $0.dollars > 0 || $0.tokens > 0 } }
}
