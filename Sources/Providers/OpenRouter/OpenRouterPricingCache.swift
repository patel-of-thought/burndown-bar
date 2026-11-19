import Foundation

/// Caches OpenRouter's public `/api/v1/models` pricing table for 6 hours so refresh cycles stay fast.
actor OpenRouterPricingCache {
    static let shared = OpenRouterPricingCache()

    private var cachedPrices: [String: OpenRouterModelPrice] = [:]
    private var fetchedAt: Date?
    private let ttl: TimeInterval = 6 * 3600

    func prices(using client: SubscriptionClient, force: Bool = false, now: Date = Date()) async -> [String: OpenRouterModelPrice] {
        if !force, let fetchedAt, now.timeIntervalSince(fetchedAt) < ttl, !cachedPrices.isEmpty {
            return cachedPrices
        }
        guard let json = try? await client.request(url: "https://openrouter.ai/api/v1/models", provider: "OpenRouter") else {
            return cachedPrices
        }
        let parsed = AdditionalParsers.openRouterPricing(json)
        if !parsed.isEmpty {
            cachedPrices = parsed
            fetchedAt = now
        }
        return cachedPrices
    }
}

/// Caches OpenRouter Data API global rankings (`rankings-daily`, `app-rankings`, `classifications/task`) for 1 hour.
actor OpenRouterRankingsCache {
    static let shared = OpenRouterRankingsCache()

    private var cached: OpenRouterRankingsSnapshot?
    private var cachedKeySuffix: String?
    private var fetchedAt: Date?
    private let ttl: TimeInterval = 3600

    static func modelsURL(now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let start = calendar.date(byAdding: .day, value: -59, to: end)!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "https://openrouter.ai/api/v1/datasets/rankings-daily?start_date=\(formatter.string(from: start))&end_date=\(formatter.string(from: end))"
    }

    func rankings(standardKey: String, using client: SubscriptionClient, force: Bool = false, now: Date = Date()) async -> OpenRouterRankingsSnapshot? {
        let suffix = String(standardKey.suffix(8))
        if !force, cachedKeySuffix == suffix, let fetchedAt, now.timeIntervalSince(fetchedAt) < ttl, let cached {
            return cached
        }
        let headers = ["Authorization": "Bearer \(standardKey)"]
        async let modelsReq = try? client.request(url: Self.modelsURL(now: now), provider: "OpenRouter", headers: headers)
        async let appsReq = try? client.request(url: "https://openrouter.ai/api/v1/datasets/app-rankings?sort=popular", provider: "OpenRouter", headers: headers)
        async let tasksReq = try? client.request(url: "https://openrouter.ai/api/v1/classifications/task", provider: "OpenRouter", headers: headers)

        let snapshot = AdditionalParsers.openRouterRankings(modelsJSON: await modelsReq, appsJSON: await appsReq, tasksJSON: await tasksReq)
        if let snapshot {
            cached = snapshot
            cachedKeySuffix = suffix
            fetchedAt = now
        }
        return snapshot ?? (cachedKeySuffix == suffix ? cached : nil)
    }
}
