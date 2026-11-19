import Foundation

struct GrokBilling {
    var windows: [QuotaWindow] = []
    var balanceUSD: Double?
    var plan: String?

    static func parse(_ responses: [JSON]) -> GrokBilling {
        var result = GrokBilling()
        func amount(_ raw: Any?) -> Double? {
            if let object = raw as? JSON { return number(object["val"]) }
            return number(raw)
        }
        for config in responses {
            let period = config["currentPeriod"] as? JSON ?? config["current_period"] as? JSON ?? [:]
            let products = config["productUsage"] as? [JSON] ?? config["product_usage"] as? [JSON] ?? []
            let usedCredits = number(config["creditUsagePercent"] ?? config["credit_usage_percent"])
            let type = string(period["type"])?.lowercased() ?? ""
            let creditsMode = usedCredits != nil || type.contains("weekly") || !products.isEmpty
            let start = date(period["start"] ?? config["billingPeriodStart"] ?? config["billing_period_start"])
            let end = date(period["end"] ?? config["billingPeriodEnd"] ?? config["billing_period_end"])
            let duration = start.flatMap { start in end.flatMap { $0 > start ? $0.timeIntervalSince(start) : nil } }
                ?? (creditsMode && !type.contains("monthly") ? 604800 : nil)
            let limit = amount(config["monthlyLimit"] ?? config["monthly_limit"])
            let used = amount(config["used"])
            let included = used.flatMap { used in limit.map { min(used, $0) } ?? used }
            func append(_ id: String, _ title: String, _ percent: Double?, reset: Date?, period: Double?) {
                let window = QuotaWindow(id: id, title: title, remaining: percent.map { max(0, min(100, 100 - $0)) }, reset: reset, period: period)
                if let index = result.windows.firstIndex(where: { $0.id == id }) {
                    if result.windows[index].remaining == nil && window.remaining != nil { result.windows[index] = window }
                } else { result.windows.append(window) }
            }
            if creditsMode {
                append("grok-credits", type.contains("monthly") ? "Monthly credits" : "Weekly credits", usedCredits, reset: end, period: duration)
                for (index, product) in products.enumerated() {
                    let label = string(product["product"]) ?? "Product \(index + 1)"
                    append("grok-product-\(label)", label, number(product["usagePercent"] ?? product["usage_percent"]), reset: end, period: duration)
                }
            }
            if let limit, limit > 0, let included {
                let reset = date(config["billingPeriodEnd"] ?? config["billing_period_end"])
                let start = date(config["billingPeriodStart"] ?? config["billing_period_start"])
                append("grok-monthly", "Monthly allowance", included / limit * 100, reset: reset,
                       period: start.flatMap { start in reset.flatMap { $0 > start ? $0.timeIntervalSince(start) : nil } })
                if result.plan == nil { result.plan = limit == 150000 ? "SuperGrok Heavy" : limit == 15000 ? "SuperGrok" : nil }
            }
            let cap = amount(config["onDemandCap"] ?? config["on_demand_cap"])
            let overage = amount(config["onDemandUsed"] ?? config["on_demand_used"])
                ?? used.flatMap { used in limit.map { max(0, used - $0) } }
            if let cap, cap > 0, let overage {
                append("grok-on-demand", "On-demand allowance", overage / cap * 100,
                       reset: date(config["billingPeriodEnd"] ?? config["billing_period_end"]), period: nil)
            }
            result.balanceUSD = result.balanceUSD ?? amount(config["prepaidBalance"] ?? config["prepaid_balance"]).map { $0 / 100 }
            result.plan = string(config["subscriptionTierDisplay"] ?? config["subscription_tier_display"] ?? config["subscriptionTier"] ?? config["subscription_tier"]) ?? result.plan
        }
        return result
    }
}
