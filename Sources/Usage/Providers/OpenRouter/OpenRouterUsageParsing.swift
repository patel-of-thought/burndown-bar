import Foundation

extension AdditionalParsers {
    /// Parses a Standard OpenRouter API key (`GET /api/v1/key`) into an `Account`.
    static func openRouterStandardKey(_ raw: JSON, now: Date = Date(), calendar: Calendar = utcCalendar()) throws -> Account {
        let data = (raw["data"] as? JSON) ?? raw
        guard data["usage"] != nil || data["limit"] != nil || data["label"] != nil else {
            throw SubscriptionError.message("OpenRouter did not return a recognized key payload.")
        }
        let label = string(data["label"]) ?? string(data["name"]) ?? "OpenRouter key"
        var account = withIdentity(SubscriptionClient.placeholder(.openrouter), email: label)
        account.plan = (data["is_free_tier"] as? Bool == true) ? "Free tier" : "Pay-as-you-go"
        account.updatedAt = now

        let limit = number(data["limit"])
        let limitRemaining = number(data["limit_remaining"])
        let resetKind = string(data["limit_reset"])
        if let limit, limit > 0 {
            let remaining = limitRemaining ?? max(0, limit - (number(data["usage"]) ?? 0))
            let pct = max(0, min(100, remaining / limit * 100))
            let resetInfo = openRouterResetWindow(kind: resetKind, now: now, calendar: calendar)
            account.windows.append(QuotaWindow(
                id: "openrouter-key-limit",
                title: resetKind.map { "\($0.capitalized) key cap" } ?? "Key cap",
                remaining: pct,
                reset: resetInfo?.reset,
                period: resetInfo?.period
            ))
            account.credits = remaining.formatted(.currency(code: "USD"))
        }

        let daily = number(data["usage_daily"])
        let weekly = number(data["usage_weekly"])
        let monthly = number(data["usage_monthly"])
        let total = number(data["usage"])
        let byokTotal = number(data["byok_usage"])
        let byokMonthly = number(data["byok_usage_monthly"])

        if daily != nil || monthly != nil {
            account.costs = UsageCosts(
                today: CostPeriod(dollars: daily, tokens: nil, isComplete: true),
                last30Days: CostPeriod(dollars: monthly ?? total, tokens: nil, isComplete: monthly != nil),
                updatedAt: now,
                warning: "Standard API key: token and cache history require a Management Key."
            )
        }

        account.facts.append(UsageFact(label: "Key mode", value: "Standard key (USD limits only)"))
        if let daily { account.facts.append(UsageFact(label: "Today spend", value: daily.formatted(.currency(code: "USD")))) }
        if let weekly { account.facts.append(UsageFact(label: "Weekly spend", value: weekly.formatted(.currency(code: "USD")))) }
        if let monthly { account.facts.append(UsageFact(label: "Monthly spend", value: monthly.formatted(.currency(code: "USD")))) }
        if let byok = byokMonthly ?? byokTotal, byok > 0 {
            account.facts.append(UsageFact(label: "BYOK spend", value: byok.formatted(.currency(code: "USD"))))
        }
        account.details = ProviderDetails(
            source: "OpenRouter Standard Key",
            warning: "Connected with a standard API key. Add a Management Key for account credits, 30-day token/cache charts, and key controls.",
            dashboardURL: URL(string: AccountOrigin.openrouter.dashboard)
        )
        account.openRouter = OpenRouterSnapshot(isManagementKey: false, hasStandardKey: true, byokSpend30dUSD: byokMonthly ?? byokTotal)
        return account
    }

    static func openRouterRankings(modelsJSON: JSON?, appsJSON: JSON?, tasksJSON: JSON?) -> OpenRouterRankingsSnapshot? {
        let meta = (modelsJSON?["meta"] as? JSON) ?? (appsJSON?["meta"] as? JSON) ?? (tasksJSON?["meta"] as? JSON)
        let asOf = string(meta?["as_of"])

        // Aggregate daily top-50 rows into the same trailing windows used by OpenRouter's leaderboard.
        var modelPeriods: [OpenRouterRankingPeriod: [OpenRouterGlobalModelRank]] = [:]
        if let rows = modelsJSON?["data"] as? [JSON], !rows.isEmpty {
            let latestDate = rows.compactMap { string($0["date"]) }.max()
            if let latestDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                if let end = formatter.date(from: latestDate) {
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                    for period in OpenRouterRankingPeriod.allCases {
                        let start = calendar.date(byAdding: .day, value: 1 - period.days, to: end)!
                        let previousStart = calendar.date(byAdding: .day, value: 1 - period.days * 2, to: end)!
                        var current: [String: Int64] = [:]
                        var previous: [String: Int64] = [:]
                        var totalAll: Int64 = 0
                        for row in rows {
                            guard let day = string(row["date"]), let date = formatter.date(from: day),
                                  let slug = string(row["model_permaslug"] ?? row["model"]) else { continue }
                            let tokens = rankingTokens(row["total_tokens"])
                            if date >= start && date <= end {
                                totalAll += tokens
                                if slug != "other" { current[slug, default: 0] += tokens }
                            } else if date >= previousStart && date < start && slug != "other" {
                                previous[slug, default: 0] += tokens
                            }
                        }
                        modelPeriods[period] = current.sorted {
                            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
                        }.prefix(20).map { slug, tokens in
                            let before = previous[slug] ?? 0
                            return OpenRouterGlobalModelRank(model: slug, totalTokens: tokens,
                                sharePercent: totalAll > 0 ? Double(tokens) / Double(totalAll) * 100 : nil,
                                changePercent: before > 0 ? (Double(tokens) / Double(before) - 1) * 100 : nil)
                        }
                    }
                }
            }
        }

        // 2. Top apps
        var topApps: [OpenRouterGlobalAppRank] = []
        if let rows = appsJSON?["data"] as? [JSON] {
            for (idx, row) in rows.prefix(8).enumerated() {
                guard let name = string(row["app_name"] ?? row["name"] ?? row["title"]) else { continue }
                let rank = Int((number(row["rank"]) ?? Double(idx + 1)).rounded())
                let tokens = Int64((number(row["total_tokens"]) ?? 0).rounded())
                let reqs = number(row["total_requests"] ?? row["requests"]).map { Int($0.rounded()) }
                topApps.append(OpenRouterGlobalAppRank(rank: rank, name: name, totalTokens: tokens, requests: reqs))
            }
        }

        // 3. Task classifications
        var taskShares: [OpenRouterTaskShare] = []
        if let categories = tasksJSON?["categories"] as? [JSON] {
            for cat in categories {
                if let sub = cat["classifications"] as? [JSON], !sub.isEmpty {
                    for item in sub {
                        guard let name = string(item["task"] ?? item["name"]) else { continue }
                        let tokShare = normalizePercentRatio(number(item["token_share"])) ?? 0
                        let useShare = normalizePercentRatio(number(item["usage_share"])) ?? 0
                        taskShares.append(OpenRouterTaskShare(name: name, tokenSharePercent: tokShare, usageSharePercent: useShare))
                    }
                } else if let name = string(cat["category"]) {
                    let tokShare = normalizePercentRatio(number(cat["token_share"])) ?? 0
                    let useShare = normalizePercentRatio(number(cat["usage_share"])) ?? 0
                    taskShares.append(OpenRouterTaskShare(name: name, tokenSharePercent: tokShare, usageSharePercent: useShare))
                }
            }
            taskShares.sort { max($0.tokenSharePercent, $0.usageSharePercent) > max($1.tokenSharePercent, $1.usageSharePercent) }
            taskShares = Array(taskShares.prefix(8))
        }

        let snapshot = OpenRouterRankingsSnapshot(asOf: asOf, topModels: modelPeriods[.week] ?? [],
            modelPeriods: modelPeriods, topApps: topApps, taskShares: taskShares)
        return snapshot.isEmpty ? nil : snapshot
    }

    private static func rankingTokens(_ value: Any?) -> Int64 {
        if let text = value as? String, let tokens = Int64(text), tokens >= 0 { return tokens }
        if let number = value as? NSNumber { return max(0, number.int64Value) }
        return 0
    }

    /// Parses Management API payloads (`/credits`, `/keys`, `/analytics/query`, `/activity`, `/guardrails`, `/endpoints`).
    static func openRouterManagement(
        creditsJSON: JSON,
        keysJSON: JSON? = nil,
        analyticsDailyJSON: JSON? = nil,
        analyticsByKeyJSON: JSON? = nil,
        analyticsByModelJSON: JSON? = nil,
        activityJSON: JSON? = nil,
        guardrailsJSON: JSON? = nil,
        endpoints: [OpenRouterEndpointHealth] = [],
        promptIncludesCached: Bool = true,
        completionIncludesReasoning: Bool = false,
        now: Date = Date(),
        calendar: Calendar = utcCalendar()
    ) throws -> Account {
        let creditsData = (creditsJSON["data"] as? JSON) ?? creditsJSON
        guard let totalCredits = number(creditsData["total_credits"]),
              let totalUsage = number(creditsData["total_usage"]) else {
            throw SubscriptionError.message("OpenRouter did not return account credit balances.")
        }

        let remainingCredits = totalCredits - totalUsage
        var account = withIdentity(SubscriptionClient.placeholder(.openrouter), email: "OpenRouter Account")
        account.updatedAt = now
        account.credits = remainingCredits.formatted(.currency(code: "USD"))

        if totalCredits > 0 {
            let pct = max(0, min(100, remainingCredits / totalCredits * 100))
            account.windows.append(QuotaWindow(id: "openrouter-credits", title: "Account credits", remaining: pct, reset: nil, period: nil))
        }

        var keys = parseOpenRouterKeys(keysJSON)
        let activeCappedKeys = keys.filter { !$0.disabled && ($0.limitUSD ?? 0) > 0 }
        let tightestKey = activeCappedKeys.min { lhs, rhs in
            keyRemainingPercent(lhs) < keyRemainingPercent(rhs)
        }
        if let tightestKey, let limit = tightestKey.limitUSD, limit > 0 {
            let pct = keyRemainingPercent(tightestKey)
            let resetInfo = openRouterResetWindow(kind: tightestKey.limitReset, now: now, calendar: calendar)
            account.windows.append(QuotaWindow(
                id: "openrouter-key-\(tightestKey.hash)",
                title: "Key: \(tightestKey.displayName)",
                remaining: pct,
                reset: resetInfo?.reset,
                period: resetInfo?.period
            ))
        }

        let dayBuckets = thirtyDayBuckets(now: now, calendar: calendar)
        var dailyList = dayBuckets.map { DailyUsage(date: $0.date) }
        var dayIndex: [String: Int] = [:]
        for (idx, bucket) in dayBuckets.enumerated() { dayIndex[bucket.key] = idx }

        var totalRequests = 0
        var totalReasoning: Int64 = 0
        var totalOutput: Int64 = 0
        var totalCached: Int64 = 0
        var totalPrompt: Int64 = 0
        var totalSpend30d = 0.0
        var byokSpend30d = 0.0
        var cacheHitWeightedSum = 0.0
        var cacheHitWeight = 0.0
        var possibleCacheWeightedSum = 0.0
        var possibleCacheWeight = 0.0
        var hasAnalytics = false

        let analyticsRows = extractAnalyticsRows(analyticsDailyJSON)
        if !analyticsRows.isEmpty {
            hasAnalytics = true
            for row in analyticsRows {
                guard let dayKey = dayKeyFromRow(row, calendar: calendar), let idx = dayIndex[dayKey] else { continue }
                let spend = number(row["total_usage"] ?? row["spend"]) ?? 0
                let prompt = Int64((number(row["prompt_tokens"]) ?? 0).rounded())
                let completion = Int64((number(row["completion_tokens"]) ?? 0).rounded())
                let reasoning = Int64((number(row["reasoning_tokens"]) ?? 0).rounded())
                let cached = Int64((number(row["cached_tokens"]) ?? 0).rounded())
                let reqs = Int((number(row["request_count"] ?? row["requests"]) ?? 0).rounded())

                let freshInput = promptIncludesCached ? max(0, prompt - cached) : prompt
                let visibleAndThinkingOutput = completionIncludesReasoning ? completion : (completion + reasoning)

                dailyList[idx].dollars += spend
                dailyList[idx].input += freshInput
                dailyList[idx].output += visibleAndThinkingOutput
                dailyList[idx].cacheRead += cached

                totalRequests += reqs
                totalSpend30d += spend
                totalPrompt += prompt
                totalCached += cached
                totalReasoning += reasoning
                totalOutput += completion
                if let byok = number(row["byok_usage"] ?? row["byok_usage_inference"]) { byokSpend30d += byok }
                if let rate = normalizePercentRatio(number(row["cache_hit_rate"])), prompt > 0 {
                    cacheHitWeightedSum += rate * Double(prompt)
                    cacheHitWeight += Double(prompt)
                }
                if let possibleRate = normalizePercentRatio(number(row["possible_cache_hit_rate"])), prompt > 0 {
                    possibleCacheWeightedSum += possibleRate * Double(prompt)
                    possibleCacheWeight += Double(prompt)
                }
            }
        } else if let activityRows = (activityJSON?["data"] as? [JSON]) {
            hasAnalytics = !activityRows.isEmpty
            for row in activityRows {
                guard let dayKey = dayKeyFromRow(row, calendar: calendar), let idx = dayIndex[dayKey] else { continue }
                let spend = number(row["usage"]) ?? 0
                let prompt = Int64((number(row["prompt_tokens"]) ?? 0).rounded())
                let completion = Int64((number(row["completion_tokens"]) ?? 0).rounded())
                let reasoning = Int64((number(row["reasoning_tokens"]) ?? 0).rounded())
                let cached = Int64((number(row["cached_tokens"]) ?? 0).rounded())
                let reqs = Int((number(row["requests"]) ?? 0).rounded())

                dailyList[idx].dollars += spend
                dailyList[idx].input += max(0, prompt - cached)
                dailyList[idx].output += completion + reasoning
                dailyList[idx].cacheRead += cached

                totalRequests += reqs
                totalSpend30d += spend
                totalPrompt += prompt
                totalCached += cached
                totalReasoning += reasoning
                totalOutput += completion
                if let byok = number(row["byok_usage_inference"]) { byokSpend30d += byok }
            }
        }

        let todayDay = dailyList.last ?? DailyUsage(date: calendar.startOfDay(for: now))
        let totalTokens30d = dailyList.reduce(Int64(0)) { $0 + $1.tokens }
        account.costs = UsageCosts(
            today: CostPeriod(dollars: todayDay.dollars, tokens: todayDay.tokens, isComplete: !analyticsRows.isEmpty),
            last30Days: CostPeriod(dollars: totalSpend30d, tokens: totalTokens30d, isComplete: hasAnalytics),
            updatedAt: now,
            warning: analyticsRows.isEmpty && hasAnalytics ? "Using /activity (completed UTC days only)." : nil,
            daily: dailyList
        )

        // Per-key 30d breakdown + chart series
        var keySeries: [UsageSeries] = []
        let keyRows = extractAnalyticsRows(analyticsByKeyJSON)
        if !keyRows.isEmpty {
            let keyLookup = Dictionary(keys.map { ($0.hash, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            var perKeyDays: [String: [DailyUsage]] = [:]
            var perKeyTotals: [String: (spend: Double, tokens: Int64, cached: Int64, prompt: Int64)] = [:]
            for row in keyRows {
                let rawKeyID = string(row["api_key"] ?? row["api_key_hash"] ?? row["key_hash"]) ?? "unknown"
                let spend = number(row["total_usage"] ?? row["spend"]) ?? 0
                let prompt = Int64((number(row["prompt_tokens"]) ?? 0).rounded())
                let completion = Int64((number(row["completion_tokens"]) ?? 0).rounded())
                let reasoning = Int64((number(row["reasoning_tokens"]) ?? 0).rounded())
                let cached = Int64((number(row["cached_tokens"]) ?? 0).rounded())
                let freshInput = promptIncludesCached ? max(0, prompt - cached) : prompt
                let out = completionIncludesReasoning ? completion : (completion + reasoning)

                if let dayKey = dayKeyFromRow(row, calendar: calendar), let idx = dayIndex[dayKey] {
                    if perKeyDays[rawKeyID] == nil { perKeyDays[rawKeyID] = dayBuckets.map { DailyUsage(date: $0.date) } }
                    perKeyDays[rawKeyID]![idx].dollars += spend
                    perKeyDays[rawKeyID]![idx].input += freshInput
                    perKeyDays[rawKeyID]![idx].output += out
                    perKeyDays[rawKeyID]![idx].cacheRead += cached
                }
                var agg = perKeyTotals[rawKeyID] ?? (0, 0, 0, 0)
                agg.spend += spend
                agg.tokens += freshInput + out + cached
                agg.cached += cached
                agg.prompt += prompt
                perKeyTotals[rawKeyID] = agg
            }
            for i in keys.indices {
                if let agg = perKeyTotals[keys[i].hash] ?? perKeyTotals[keys[i].name] {
                    keys[i].spend30dUSD = agg.spend
                    keys[i].tokens30d = agg.tokens
                    if agg.prompt > 0 { keys[i].cacheHitRate = Double(agg.cached) / Double(agg.prompt) * 100 }
                }
            }
            let sortedKeySeries = perKeyDays.sorted {
                (perKeyTotals[$0.key]?.spend ?? 0) > (perKeyTotals[$1.key]?.spend ?? 0)
            }
            for (keyID, days) in sortedKeySeries.prefix(8) {
                let title = keyLookup[keyID] ?? keyID
                let series = UsageSeries(id: "or-key-\(keyID)", title: "Key: \(title)", daily: days, hasCost: true)
                if series.hasData { keySeries.append(series) }
            }
        }
        keys.sort { ($0.spend30dUSD ?? $0.usageUSD) > ($1.spend30dUSD ?? $1.usageUSD) }

        // Model breakdown (from analyticsByModelJSON or activityJSON)
        let models = parseOpenRouterModels(analyticsByModelJSON: analyticsByModelJSON, activityJSON: activityJSON,
                                           promptIncludesCached: promptIncludesCached, completionIncludesReasoning: completionIncludesReasoning)
        let guardrails = parseOpenRouterGuardrails(guardrailsJSON)

        let cacheHitRate: Double? = cacheHitWeight > 0
            ? (cacheHitWeightedSum / cacheHitWeight)
            : (totalPrompt > 0 && totalCached > 0 ? Double(totalCached) / Double(totalPrompt) * 100 : nil)
        let possibleCacheHitRate: Double? = possibleCacheWeight > 0 ? (possibleCacheWeightedSum / possibleCacheWeight) : nil
        let blendedCostPerMillion: Double? = totalTokens30d > 0 ? (totalSpend30d / (Double(totalTokens30d) / 1_000_000)) : nil

        let activeCount = keys.filter { !$0.disabled }.count
        account.plan = keys.isEmpty ? "Pay-as-you-go" : "Pay-as-you-go · \(activeCount) active key\(activeCount == 1 ? "" : "s")"
        account.details = ProviderDetails(
            source: "OpenRouter Management API",
            extraBalanceUSD: remainingCredits,
            dashboardURL: URL(string: AccountOrigin.openrouter.dashboard)
        )

        var snapshot = OpenRouterSnapshot(
            isManagementKey: true,
            creditsTotalUSD: totalCredits,
            creditsUsedUSD: totalUsage,
            creditsRemainingUSD: remainingCredits,
            byokSpend30dUSD: byokSpend30d > 0 ? byokSpend30d : keys.reduce(0.0) { $0 + $1.byokUsageUSD },
            reasoningTokens30d: totalReasoning,
            outputTokens30d: totalOutput,
            cacheHitRate: cacheHitRate,
            possibleCacheHitRate: possibleCacheHitRate,
            blendedCostPerMillion: blendedCostPerMillion,
            keySeries: keySeries,
            keys: keys,
            models: models,
            endpoints: endpoints,
            guardrails: guardrails
        )

        if let cacheHitRate {
            let value = possibleCacheHitRate.map { String(format: "%.1f%% hit · %.1f%% cacheable", cacheHitRate, $0) }
                ?? String(format: "%.1f%% hit", cacheHitRate)
            account.facts.append(UsageFact(label: "Cache hit", value: value))
        }
        if let reasoningShare = snapshot.reasoningSharePercent {
            account.facts.append(UsageFact(
                label: "Reasoning",
                value: String(format: "%.1f%% of output (%@)", reasoningShare, compactCount(totalReasoning))
            ))
        }
        if let blendedCostPerMillion {
            account.facts.append(UsageFact(label: "Blended rate", value: "\(blendedCostPerMillion.formatted(.currency(code: "USD"))) / 1M"))
        }
        if let byok = snapshot.byokSpend30dUSD, byok > 0 {
            account.facts.append(UsageFact(label: "BYOK spend", value: byok.formatted(.currency(code: "USD"))))
        }
        if totalRequests > 0 {
            account.facts.append(UsageFact(label: "30d requests", value: compactCount(Int64(totalRequests))))
        }
        if remainingCredits > 0, totalSpend30d > 0 {
            let avgDaily = totalSpend30d / 30.0
            if avgDaily > 0.01 {
                let runwayDays = Int((remainingCredits / avgDaily).rounded())
                snapshot.statusMessage = "\(avgDaily.formatted(.currency(code: "USD")))/day avg · ~\(runwayDays)d runway"
            }
        }

        account.openRouter = snapshot
        return account
    }

    static func openRouterEndpoints(_ raw: JSON, model: String) -> [OpenRouterEndpointHealth] {
        let data = (raw["data"] as? JSON) ?? raw
        let list = (data["endpoints"] as? [JSON]) ?? (raw["data"] as? [JSON]) ?? []
        return list.compactMap { item -> OpenRouterEndpointHealth? in
            let provider = string(item["provider_name"] ?? item["name"] ?? item["tag"]) ?? "Provider"
            let status = string(item["status"]) ?? "operational"
            let uptime = normalizePercentRatio(number(item["uptime_last_30m"] ?? item["uptime"]))
            let pricing = item["pricing"] as? JSON ?? [:]
            let prompt = number(pricing["prompt"]).map { $0 * 1_000_000 }
            let completion = number(pricing["completion"]).map { $0 * 1_000_000 }
            return OpenRouterEndpointHealth(
                model: model,
                providerName: provider,
                status: status,
                uptimeLast30m: uptime,
                promptPricePerMillion: prompt,
                completionPricePerMillion: completion
            )
        }
    }

    static func openRouterPricing(_ raw: JSON) -> [String: OpenRouterModelPrice] {
        let list = (raw["data"] as? [JSON]) ?? []
        var result: [String: OpenRouterModelPrice] = [:]
        for item in list {
            guard let id = string(item["id"]) else { continue }
            let pricing = item["pricing"] as? JSON ?? [:]
            guard let prompt = number(pricing["prompt"]), let completion = number(pricing["completion"]) else { continue }
            let cacheRead = number(pricing["input_cache_read"]).map { $0 * 1_000_000 }
            let context = number(item["context_length"]).map { Int($0) }
            result[id] = OpenRouterModelPrice(
                id: id,
                promptPerMillion: prompt * 1_000_000,
                completionPerMillion: completion * 1_000_000,
                cacheReadPerMillion: cacheRead,
                contextLength: context
            )
        }
        return result
    }

    static func openRouterMetaFlags(_ raw: JSON) -> (promptIncludesCached: Bool, completionIncludesReasoning: Bool) {
        let data = (raw["data"] as? JSON) ?? raw
        let metrics = (data["metrics"] as? [JSON]) ?? []
        var promptIncludesCached = true
        var completionIncludesReasoning = false
        for metric in metrics {
            let name = string(metric["name"] ?? metric["id"]) ?? ""
            let desc = (string(metric["description"]) ?? "").lowercased()
            if name == "prompt_tokens" && desc.contains("excludes cached") { promptIncludesCached = false }
            if name == "completion_tokens" && desc.contains("includes reasoning") { completionIncludesReasoning = true }
        }
        return (promptIncludesCached, completionIncludesReasoning)
    }

    // MARK: - Helpers

    private static func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private static func parseOpenRouterKeys(_ raw: JSON?) -> [OpenRouterKeySummary] {
        let list = (raw?["data"] as? [JSON]) ?? []
        return list.compactMap { item -> OpenRouterKeySummary? in
            guard let hash = string(item["hash"] ?? item["id"]) else { return nil }
            let name = string(item["name"]) ?? ""
            let label = string(item["label"])
            let usage = number(item["usage"]) ?? 0
            let byok = number(item["byok_usage"]) ?? 0
            let limit = number(item["limit"])
            let limitRemaining = number(item["limit_remaining"])
            let limitReset = string(item["limit_reset"])
            let disabled = (item["disabled"] as? Bool) ?? false
            let expiresAt = date(item["expires_at"])
            return OpenRouterKeySummary(
                hash: hash, name: name, label: label, usageUSD: usage, byokUsageUSD: byok,
                limitUSD: limit, limitRemainingUSD: limitRemaining, limitReset: limitReset,
                disabled: disabled, expiresAt: expiresAt
            )
        }
    }

    private static func parseOpenRouterGuardrails(_ raw: JSON?) -> [OpenRouterGuardrail] {
        let list = (raw?["data"] as? [JSON]) ?? []
        return list.compactMap { item -> OpenRouterGuardrail? in
            guard let id = string(item["id"]) else { return nil }
            let name = string(item["name"]) ?? "Guardrail"
            let limitUSD = number(item["limit_usd"])
            let reset = string(item["reset_interval"])
            let enforceZDR = (item["enforce_zdr"] as? Bool) ?? false
            let allowedModels = (item["allowed_models"] as? [String]) ?? []
            let keyHashes = (item["key_hashes"] as? [String]) ?? []
            return OpenRouterGuardrail(id: id, name: name, limitUSD: limitUSD, resetInterval: reset,
                                       enforceZDR: enforceZDR, allowedModels: allowedModels, keyHashes: keyHashes)
        }
    }

    private static func parseOpenRouterModels(analyticsByModelJSON: JSON?, activityJSON: JSON?,
                                              promptIncludesCached: Bool, completionIncludesReasoning: Bool) -> [OpenRouterModelSummary] {
        var map: [String: OpenRouterModelSummary] = [:]
        var latWeightedP50: [String: (sum: Double, weight: Double)] = [:]
        var latWeightedP90: [String: (sum: Double, weight: Double)] = [:]
        var cacheWeighted: [String: (sum: Double, weight: Double)] = [:]

        let rows = extractAnalyticsRows(analyticsByModelJSON)
        let sourceRows = !rows.isEmpty ? rows : ((activityJSON?["data"] as? [JSON]) ?? [])
        for row in sourceRows {
            guard let model = string(row["model"] ?? row["model_permaslug"]) else { continue }
            let reqs = Int((number(row["request_count"] ?? row["requests"]) ?? 0).rounded())
            let spend = number(row["total_usage"] ?? row["usage"] ?? row["spend"]) ?? 0
            let prompt = Int64((number(row["prompt_tokens"]) ?? 0).rounded())
            let completion = Int64((number(row["completion_tokens"]) ?? 0).rounded())
            let reasoning = Int64((number(row["reasoning_tokens"]) ?? 0).rounded())
            let cached = Int64((number(row["cached_tokens"]) ?? 0).rounded())
            let totalTok = (promptIncludesCached ? prompt : prompt + cached) + (completionIncludesReasoning ? completion : completion + reasoning)

            var entry = map[model] ?? OpenRouterModelSummary(model: model, requests: 0, spendUSD: 0, tokens: 0, reasoningTokens: 0, cachedTokens: 0)
            entry.requests += reqs
            entry.spendUSD += spend
            entry.tokens += totalTok
            entry.reasoningTokens += reasoning
            entry.cachedTokens += cached
            map[model] = entry

            let w = Double(max(1, reqs))
            if let p50 = number(row["p50_latency"]) {
                let prev = latWeightedP50[model] ?? (0, 0)
                latWeightedP50[model] = (prev.sum + p50 * w, prev.weight + w)
            }
            if let p90 = number(row["p90_latency"]) {
                let prev = latWeightedP90[model] ?? (0, 0)
                latWeightedP90[model] = (prev.sum + p90 * w, prev.weight + w)
            }
            if let rate = normalizePercentRatio(number(row["cache_hit_rate"])), prompt > 0 {
                let prev = cacheWeighted[model] ?? (0, 0)
                cacheWeighted[model] = (prev.sum + rate * Double(prompt), prev.weight + Double(prompt))
            }
        }
        return map.values.map { item in
            var copy = item
            if let p50 = latWeightedP50[item.model], p50.weight > 0 { copy.p50LatencyMs = p50.sum / p50.weight }
            if let p90 = latWeightedP90[item.model], p90.weight > 0 { copy.p90LatencyMs = p90.sum / p90.weight }
            if let c = cacheWeighted[item.model], c.weight > 0 { copy.cacheHitRate = c.sum / c.weight }
            else if item.tokens > 0 && item.cachedTokens > 0 {
                copy.cacheHitRate = Double(item.cachedTokens) / Double(item.tokens) * 100
            }
            return copy
        }.sorted { $0.spendUSD > $1.spendUSD }
    }

    private static func extractAnalyticsRows(_ raw: JSON?) -> [JSON] {
        guard let raw else { return [] }
        if let inner = raw["data"] as? JSON, let rows = inner["data"] as? [JSON] { return rows }
        if let rows = raw["data"] as? [JSON] { return rows }
        return []
    }

    private static func keyRemainingPercent(_ key: OpenRouterKeySummary) -> Double {
        guard let limit = key.limitUSD, limit > 0 else { return 100 }
        let remaining = key.limitRemainingUSD ?? max(0, limit - key.usageUSD)
        return max(0, min(100, remaining / limit * 100))
    }

    private static func normalizePercentRatio(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return value <= 1.0 ? value * 100 : value
    }

    private static func dayKeyFromRow(_ row: JSON, calendar: Calendar) -> String? {
        guard let rawDate = string(row["date__day"] ?? row["date"] ?? row["timestamp"]) else { return nil }
        if rawDate.count >= 10 {
            let prefix = String(rawDate.prefix(10))
            if prefix.count == 10 && prefix[prefix.index(prefix.startIndex, offsetBy: 4)] == "-" {
                return prefix
            }
        }
        guard let parsed = date(rawDate) else { return nil }
        return dayFormatter(calendar: calendar).string(from: parsed)
    }

    private static func thirtyDayBuckets(now: Date, calendar: Calendar) -> [(date: Date, key: String)] {
        let today = calendar.startOfDay(for: now)
        let formatter = dayFormatter(calendar: calendar)
        return (-29...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return (day, formatter.string(from: day))
        }
    }

    private static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func openRouterResetWindow(kind: String?, now: Date, calendar: Calendar) -> (reset: Date, period: TimeInterval)? {
        switch kind?.lowercased() {
        case "daily":
            let start = calendar.startOfDay(for: now)
            guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return (next, 86400)
        case "weekly":
            var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            comps.weekday = 2 // Monday in Gregorian calendar
            let monday = calendar.date(from: comps) ?? calendar.startOfDay(for: now)
            let next = monday > now ? monday : (calendar.date(byAdding: .day, value: 7, to: monday) ?? monday)
            return (next, 604800)
        case "monthly":
            let comps = calendar.dateComponents([.year, .month], from: now)
            let monthStart = calendar.date(from: comps) ?? calendar.startOfDay(for: now)
            guard let next = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return nil }
            return (next, next.timeIntervalSince(monthStart))
        default:
            return nil
        }
    }
}
