import Foundation

extension SubscriptionClient {
    func fetchOpenRouter(key suppliedKey: String?, standardKey suppliedStandardKey: String? = nil, now: Date = Date(), useRankingsCache: Bool = true) async throws -> (account: Account, source: String) {
        let primaryKey = suppliedKey ?? SubscriptionCredentials.namedKey(account: "openrouter-key", variable: "OPENROUTER_MANAGEMENT_KEY")
        let extraStandardKey = suppliedStandardKey ?? SubscriptionCredentials.namedKey(account: "openrouter-standard-key", variable: "OPENROUTER_API_KEY")

        guard let activeKey = primaryKey ?? extraStandardKey else {
            throw SubscriptionError.message("Enter an OpenRouter Management Key and/or Standard API Key in Connections.")
        }
        let headers = ["Authorization": "Bearer \(activeKey)"]
        let creditsResult = try await requestStatus(url: "https://openrouter.ai/api/v1/credits", provider: "OpenRouter", headers: headers)
        if creditsResult.status == 401 {
            throw SubscriptionError.unauthorized("OpenRouter")
        }
        if creditsResult.status == 403 {
            // Standard inference keys cannot read /credits; fall back to /api/v1/key + Data API rankings.
            let keyJSON = try await request(url: "https://openrouter.ai/api/v1/key", provider: "OpenRouter", headers: headers)
            var account = try AdditionalParsers.openRouterStandardKey(keyJSON, now: now)
            let dataKey = extraStandardKey ?? activeKey
            account.openRouter?.hasStandardKey = true
            account.openRouter?.rankings = await loadOpenRouterRankings(standardKey: dataKey, useCache: useRankingsCache, now: now)
            return (account, "OpenRouter Standard API Key")
        }
        guard (200...299).contains(creditsResult.status), let creditsJSON = creditsResult.value as? JSON else {
            throw SubscriptionError.http(creditsResult.status)
        }

        let keysTask = Task { try? await self.request(url: "https://openrouter.ai/api/v1/keys", provider: "OpenRouter", headers: headers) }
        let metaTask = Task { try? await self.request(url: "https://openrouter.ai/api/v1/analytics/meta", provider: "OpenRouter", headers: headers) }
        let guardrailsTask = Task { try? await self.request(url: "https://openrouter.ai/api/v1/guardrails", provider: "OpenRouter", headers: headers) }
        let dailyTask = Task { await self.queryOpenRouterAnalytics(headers: headers, dimensions: [], extraMetrics: ["cache_hit_rate", "possible_cache_hit_rate", "blended_cost_per_million_tokens"], now: now) }
        let byKeyTask = Task { await self.queryOpenRouterAnalytics(headers: headers, dimensions: ["api_key"], extraMetrics: ["cache_hit_rate"], now: now) }
        let byModelTask = Task { await self.queryOpenRouterAnalytics(headers: headers, dimensions: ["model"], extraMetrics: ["cache_hit_rate", "p50_latency", "p90_latency"], days: 7, now: now) }
        let rankingsTask = Task<OpenRouterRankingsSnapshot?, Never> {
            await self.loadOpenRouterRankings(standardKey: extraStandardKey ?? activeKey, useCache: useRankingsCache, now: now)
        }

        let keysJSON = await keysTask.value
        let metaFlags = (await metaTask.value).map(AdditionalParsers.openRouterMetaFlags(_:)) ?? (promptIncludesCached: true, completionIncludesReasoning: false)
        let guardrailsJSON = await guardrailsTask.value
        let analyticsDaily = await dailyTask.value
        let analyticsByKey = await byKeyTask.value
        let analyticsByModel = await byModelTask.value

        var activityJSON: JSON?
        if analyticsDaily == nil || analyticsByModel == nil {
            activityJSON = try? await request(url: "https://openrouter.ai/api/v1/activity", provider: "OpenRouter", headers: headers)
        }

        // Pre-parse models so we know the top 3 active models to check endpoint health for.
        let preliminary = try AdditionalParsers.openRouterManagement(
            creditsJSON: creditsJSON,
            keysJSON: keysJSON,
            analyticsDailyJSON: analyticsDaily,
            analyticsByKeyJSON: analyticsByKey,
            analyticsByModelJSON: analyticsByModel,
            activityJSON: activityJSON,
            guardrailsJSON: guardrailsJSON,
            promptIncludesCached: metaFlags.promptIncludesCached,
            completionIncludesReasoning: metaFlags.completionIncludesReasoning,
            now: now
        )
        let topModels = Array((preliminary.openRouter?.models ?? []).prefix(3).map(\.model))
        let endpoints = await fetchOpenRouterEndpoints(models: topModels, headers: headers)
        _ = await OpenRouterPricingCache.shared.prices(using: self, now: now)

        var account = preliminary
        account.openRouter?.endpoints = endpoints
        account.openRouter?.hasStandardKey = extraStandardKey != nil
        account.openRouter?.rankings = await rankingsTask.value
        let source = extraStandardKey != nil ? "OpenRouter Management + Standard Keys" : "OpenRouter Management API"
        return (account, source)
    }

    private func loadOpenRouterRankings(standardKey: String, useCache: Bool, now: Date) async -> OpenRouterRankingsSnapshot? {
        if useCache {
            return await OpenRouterRankingsCache.shared.rankings(standardKey: standardKey, using: self, now: now)
        }
        let headers = ["Authorization": "Bearer \(standardKey)"]
        async let modelsReq = try? request(url: OpenRouterRankingsCache.modelsURL(now: now), provider: "OpenRouter", headers: headers)
        async let appsReq = try? request(url: "https://openrouter.ai/api/v1/datasets/app-rankings?sort=popular", provider: "OpenRouter", headers: headers)
        return AdditionalParsers.openRouterRankings(modelsJSON: await modelsReq, appsJSON: await appsReq)
    }

    private func queryOpenRouterAnalytics(headers: [String: String], dimensions: [String], extraMetrics: [String], days: Int = 30, now: Date) async -> JSON? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = utc.date(byAdding: .day, value: -(days - 1), to: utc.startOfDay(for: now)) ?? now.addingTimeInterval(-Double(days) * 86400)
        let baseMetrics = ["request_count", "total_usage", "prompt_tokens", "completion_tokens", "reasoning_tokens", "cached_tokens"]

        let fullBody: JSON = [
            "time_range": ["start": iso.string(from: start), "end": iso.string(from: now)],
            "granularity": "day",
            "metrics": baseMetrics + extraMetrics,
            "dimensions": dimensions,
            "limit": 500
        ]
        if let result = try? await requestStatus(url: "https://openrouter.ai/api/v1/analytics/query", provider: "OpenRouter", method: "POST", headers: headers, body: fullBody) {
            if (200...299).contains(result.status), let json = result.value as? JSON { return json }
            if result.status == 400 && !extraMetrics.isEmpty {
                // Workspace-scoped keys reject optional metrics such as possible_cache_hit_rate or latency percentiles.
                let fallbackBody: JSON = [
                    "time_range": ["start": iso.string(from: start), "end": iso.string(from: now)],
                    "granularity": "day",
                    "metrics": baseMetrics,
                    "dimensions": dimensions,
                    "limit": 500
                ]
                if let retry = try? await requestStatus(url: "https://openrouter.ai/api/v1/analytics/query", provider: "OpenRouter", method: "POST", headers: headers, body: fallbackBody),
                   (200...299).contains(retry.status), let json = retry.value as? JSON {
                    return json
                }
            }
        }
        return nil
    }

    private func fetchOpenRouterEndpoints(models: [String], headers: [String: String]) async -> [OpenRouterEndpointHealth] {
        guard !models.isEmpty else { return [] }
        return await withTaskGroup(of: [OpenRouterEndpointHealth].self) { group in
            for model in models {
                let parts = model.split(separator: "/", maxSplits: 1).map(String.init)
                guard parts.count == 2, Self.safeID(parts[0]), Self.safeSlug(parts[1]) else { continue }
                group.addTask {
                    let url = "https://openrouter.ai/api/v1/models/\(parts[0])/\(parts[1])/endpoints"
                    guard let json = try? await self.request(url: url, provider: "OpenRouter", headers: headers) else { return [] }
                    return Array(AdditionalParsers.openRouterEndpoints(json, model: model).prefix(3))
                }
            }
            var combined: [OpenRouterEndpointHealth] = []
            for await items in group { combined.append(contentsOf: items) }
            return combined
        }
    }

    static func safeSlug(_ value: String) -> Bool {
        !value.isEmpty && value.count < 200 && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._-:".unicodeScalars.contains($0) }
    }
}
