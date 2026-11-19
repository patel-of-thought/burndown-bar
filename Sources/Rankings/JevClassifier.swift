import Foundation

struct JevClassifierConfig: Codable, Equatable {
    var jevModel: String = "typesafe/jev-1.14"
    var pricingWeight: Double = 0.30
    var cheapnessWeight: Double = 0.25
    var intelligenceWeight: Double = 0.30
    var tokenUsageWeight: Double = 0.15
    var maxBlendedPriceUSD: Double? = nil
    var maxCandidates: Int = 8
    var excludedModels: String = ""
    var autoClassify: Bool = true

    static let presets: [(id: String, name: String)] = [
        ("typesafe/jev-1.14", "Jev 1.14"),
        ("google/gemini-decision-1", "Gemini Decision 1"),
        ("openai/gpt-6-luna-decisions", "OpenAI GPT-6 Luna Decisions"),
        ("perplexity/pplx-decider-v1.3:free", "Perplexity Decider v1.3 (Free)"),
        ("cloudflare/clef-flash", "Cloudflare Clef Flash")
    ]

    var normalizedWeights: (pricing: Double, cheapness: Double, intelligence: Double, tokenUsage: Double) {
        let p = max(0, pricingWeight)
        let c = max(0, cheapnessWeight)
        let i = max(0, intelligenceWeight)
        let u = max(0, tokenUsageWeight)
        let total = p + c + i + u
        guard total > 0 else { return (0.25, 0.25, 0.25, 0.25) }
        return (p / total, c / total, i / total, u / total)
    }

    var excludedTerms: [String] {
        excludedModels
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    var resolvedJevModel: String {
        let trimmed = jevModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "typesafe/jev-1.14" : trimmed
    }

    var clampedMaxCandidates: Int {
        max(4, min(12, maxCandidates))
    }
}

struct JevModelCandidate: Identifiable {
    let key: String
    let modelID: String
    let displayName: String
    let promptPerMillion: Double?
    let completionPerMillion: Double?
    let intelligence: Double?
    let costPerTaskUSD: Double?
    let cheapnessScore: Double?
    let userTokens: Int64?

    var id: String { key }

    /// Weighted blended price per 1M tokens (3:1 prompt:completion ratio).
    var blendedPerMillion: Double? {
        switch (promptPerMillion, completionPerMillion) {
        case let (p?, c?): return (p * 3 + c) / 4
        case let (p?, nil): return p
        case let (nil, c?): return c
        case (nil, nil): return nil
        }
    }

    var priceLabel: String {
        switch (promptPerMillion, completionPerMillion) {
        case let (p?, c?): return String(format: "$%.2f / $%.2f per 1M", p, c)
        case let (p?, nil): return String(format: "$%.2f / 1M in", p)
        case let (nil, c?): return String(format: "$%.2f / 1M out", c)
        case (nil, nil):
            if let task = costPerTaskUSD { return String(format: "$%.2f / task", task) }
            return "Pricing n/a"
        }
    }
}

struct JevUsageContext {
    let task: String
    let config: JevClassifierConfig
    let totalTokens30d: Int64
    let openRouterSpend30dUSD: Double?
    let openRouterCreditsRemainingUSD: Double?
    let blendedCostPerMillionUSD: Double?
    let cacheHitRatePercent: Double?
    let reasoningSharePercent: Double?
    let lowestQuotaRemainingPercent: Double?
    let activeProviders: [String]
    let topUsedModels: [(model: String, tokens: Int64, spendUSD: Double)]
    let candidates: [JevModelCandidate]

    var averageCandidateBlendedPrice: Double? {
        let prices = candidates.compactMap(\.blendedPerMillion).filter { $0 > 0 }
        guard !prices.isEmpty else { return nil }
        return prices.reduce(0, +) / Double(prices.count)
    }

    var cheapestCandidate: JevModelCandidate? {
        candidates.filter { ($0.blendedPerMillion ?? .infinity) > 0 }
            .min { ($0.blendedPerMillion ?? .infinity) < ($1.blendedPerMillion ?? .infinity) }
    }

    var highestIntelligenceCandidate: JevModelCandidate? {
        candidates.filter { $0.intelligence != nil }
            .max { ($0.intelligence ?? 0) < ($1.intelligence ?? 0) }
    }
}

enum JevModelTier: String, CaseIterable {
    case budget, balanced, frontier
    var title: String {
        switch self {
        case .budget: return "Budget"
        case .balanced: return "Balanced"
        case .frontier: return "Frontier"
        }
    }
}

struct JevClassificationResult {
    let requestID: String?
    let jevModel: String
    let provider: String
    let recommendedCandidate: JevModelCandidate?
    let recommendedKey: String
    let modelConfidence: Double
    let modelProbabilities: [(candidate: JevModelCandidate?, key: String, probability: Double)]
    let tier: JevModelTier
    let tierConfidence: Double
    let spendEfficiencyScore: Int
    let spendEfficiencyLegend: String
    let spendEfficiencyConfidence: Double
    let prioritizeCheapnessProbability: Double
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double?
    let context: JevUsageContext
    let classifiedAt: Date
}

enum JevClassifierError: LocalizedError {
    case missingKey
    case unauthorized
    case insufficientCredits
    case rateLimited
    case unavailable(Int, String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add an OpenRouter Standard API Key in Connections to use Model Advisor."
        case .unauthorized:
            return "OpenRouter rejected the API key. Ensure a Standard API Key (not only a Management Key) is saved in Connections."
        case .insufficientCredits:
            return "OpenRouter credits are insufficient to get model advice."
        case .rateLimited:
            return "OpenRouter rate limit reached for Model Advisor. Try again shortly."
        case .unavailable(let status, let detail):
            if let detail, !detail.isEmpty { return "Model Advisor returned HTTP \(status): \(detail)" }
            return "Model Advisor returned HTTP \(status). Try again later."
        case .invalidResponse:
            return "Model Advisor returned an unexpected decision response."
        }
    }
}

enum JevContextBuilder {
    static let fallbackModels: [(id: String, name: String, prompt: Double, completion: Double, intelligence: Double)] = [
        ("anthropic/claude-sonnet-4", "Claude Sonnet 4", 3.00, 15.00, 61),
        ("openai/gpt-4.1", "GPT-4.1", 2.00, 8.00, 58),
        ("openai/gpt-4.1-mini", "GPT-4.1 Mini", 0.40, 1.60, 51),
        ("google/gemini-2.5-pro", "Gemini 2.5 Pro", 1.25, 10.00, 62),
        ("google/gemini-2.5-flash", "Gemini 2.5 Flash", 0.15, 0.60, 52),
        ("deepseek/deepseek-chat-v3-0324", "DeepSeek V3", 0.27, 1.10, 50)
    ]

    /// Excludes decision classifiers, meta-routers, and non-LLM models (embeddings, moderation, image, audio)
    /// so only generative LLMs appear in classification results.
    static func isEligibleLLM(modelID: String, displayName: String = "", excludedTerms: [String] = []) -> Bool {
        if JevClassifierConfig.presets.contains(where: { $0.id.caseInsensitiveCompare(modelID) == .orderedSame }) { return false }
        let combined = "\(modelID) \(displayName)".lowercased()
        let blockedSubstrings = [
            "typesafe/", "jev-", "jev ", "/jev", "jev1", "jev_",
            "openrouter/auto", "openrouter/free", "switchpoint/router", "/router",
            "embedding", "embed-", "rerank", "moderation", "guard",
            "whisper", "tts", "dall-e", "stable-diffusion", "midjourney", "flux",
            "imagen", "sora", "veo"
        ]
        if blockedSubstrings.contains(where: { combined.contains($0) }) { return false }
        let tokens = combined.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if tokens.contains("jev") { return false }
        for term in excludedTerms where combined.contains(term) {
            return false
        }
        return true
    }

    /// Computes a 5–100 cheapness score anchored on real-world LLM pricing ($0.10/1M -> 100, $30/1M -> 5).
    static func cheapnessScore(forBlendedPerMillion blended: Double) -> Double {
        let clamped = max(0.10, blended)
        let logMin = log10(0.10)
        let logMax = log10(30.0)
        let ratio = (log10(clamped) - logMin) / (logMax - logMin)
        return max(5, min(100, ((1.0 - ratio) * 95.0 + 5.0).rounded()))
    }

    static func build(
        accounts: [Account],
        localUsage: [String: [UsageSeries]],
        artificialAnalysis: ArtificialAnalysisSnapshot?,
        prices: [String: OpenRouterModelPrice],
        task: String,
        config: JevClassifierConfig = JevClassifierConfig()
    ) -> JevUsageContext {
        let openRouter = accounts.first(where: { $0.origin == .openrouter })?.openRouter

        let openRouterTokens = openRouter?.models.reduce(Int64(0)) { $0 + $1.tokens } ?? 0
        let accountCostTokens = accounts.filter { $0.origin != .openrouter }
            .reduce(Int64(0)) { $0 + ($1.costs?.last30Days.tokens ?? 0) }
        let localTokens = localUsage.values.joined().reduce(Int64(0)) { total, series in
            total + series.daily.reduce(Int64(0)) { $0 + $1.tokens }
        }
        let totalTokens30d = openRouterTokens + accountCostTokens + localTokens
        let openRouterSpend = openRouter?.models.reduce(0.0) { $0 + $1.spendUSD }
        let lowestQuota = accounts.filter { !$0.disabled && !$0.isStale }.compactMap(\.minimum).min()
        let activeProviders = Array(Set(accounts.filter { !$0.disabled && $0.updatedAt != nil }.map(\.providerName))).sorted()
        let topUsedModels = (openRouter?.models ?? [])
            .filter { isEligibleLLM(modelID: $0.model) }
            .sorted { $0.tokens > $1.tokens }
            .prefix(5)
            .map { (model: $0.model, tokens: $0.tokens, spendUSD: $0.spendUSD) }

        let candidates = buildCandidates(
            openRouter: openRouter,
            artificialAnalysis: artificialAnalysis,
            prices: prices,
            config: config
        )

        return JevUsageContext(
            task: task.trimmingCharacters(in: .whitespacesAndNewlines),
            config: config,
            totalTokens30d: totalTokens30d,
            openRouterSpend30dUSD: (openRouterSpend ?? 0) > 0 ? openRouterSpend : openRouter?.creditsUsedUSD,
            openRouterCreditsRemainingUSD: openRouter?.creditsRemainingUSD,
            blendedCostPerMillionUSD: openRouter?.blendedCostPerMillion,
            cacheHitRatePercent: openRouter?.cacheHitRate,
            reasoningSharePercent: openRouter?.reasoningSharePercent,
            lowestQuotaRemainingPercent: lowestQuota,
            activeProviders: activeProviders,
            topUsedModels: topUsedModels,
            candidates: candidates
        )
    }

    private static func buildCandidates(
        openRouter: OpenRouterSnapshot?,
        artificialAnalysis: ArtificialAnalysisSnapshot?,
        prices: [String: OpenRouterModelPrice],
        config: JevClassifierConfig
    ) -> [JevModelCandidate] {
        let excludedTerms = config.excludedTerms
        let maxCount = config.clampedMaxCandidates
        let normalizedPriceIndex: [String: OpenRouterModelPrice] = Dictionary(
            prices.values.map { (normalizedKey($0.id), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let aaByNorm: [String: ArtificialAnalysisModel] = Dictionary(
            (artificialAnalysis?.models ?? []).map { (ArtificialAnalysisParser.normalizedName($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let userTokensByModel: [String: Int64] = Dictionary(
            (openRouter?.models ?? []).map { ($0.model.lowercased(), $0.tokens) },
            uniquingKeysWith: { max($0, $1) }
        )

        var raw: [(id: String, name: String, prompt: Double?, completion: Double?, intelligence: Double?, costPerTask: Double?, userTokens: Int64?)] = []
        var seen = Set<String>()

        func blendedPrice(_ prompt: Double?, _ completion: Double?) -> Double? {
            switch (prompt, completion) {
            case let (p?, c?): return (p * 3 + c) / 4
            case let (p?, nil): return p
            case let (nil, c?): return c
            default: return nil
            }
        }

        func add(id: String, name: String, prompt: Double?, completion: Double?, intelligence: Double?, costPerTask: Double?, userTokens: Int64?) {
            guard id.caseInsensitiveCompare(config.resolvedJevModel) != .orderedSame else { return }
            guard isEligibleLLM(modelID: id, displayName: name, excludedTerms: excludedTerms) else { return }
            if let cap = config.maxBlendedPriceUSD, let blended = blendedPrice(prompt, completion), blended > cap {
                return
            }
            let norm = normalizedKey(id)
            guard !norm.isEmpty, !seen.contains(norm) else { return }
            seen.insert(norm)
            raw.append((id, name, prompt, completion, intelligence, costPerTask, userTokens))
        }

        // 1. Top Artificial Analysis LLMs (intelligence & cost per task)
        if let aaModels = artificialAnalysis?.topModels {
            for model in aaModels.prefix(maxCount) {
                guard raw.count < maxCount else { break }
                let matchedPrice = matchPrice(forName: model.name, prices: prices, normalizedIndex: normalizedPriceIndex)
                let modelID = matchedPrice?.id ?? model.id
                add(
                    id: modelID,
                    name: model.name,
                    prompt: matchedPrice?.promptPerMillion,
                    completion: matchedPrice?.completionPerMillion,
                    intelligence: model.intelligence,
                    costPerTask: model.costPerTaskUSD,
                    userTokens: userTokensByModel[modelID.lowercased()]
                )
            }
        }

        // 2. User's top used OpenRouter LLMs
        for used in (openRouter?.models ?? []).sorted(by: { $0.tokens > $1.tokens }).prefix(4) {
            guard raw.count < maxCount else { break }
            let price = prices[used.model] ?? normalizedPriceIndex[normalizedKey(used.model)]
            let aa = matchAA(forModelID: used.model, aaByNorm: aaByNorm)
            add(
                id: used.model,
                name: shortDisplayName(for: used.model),
                prompt: price?.promptPerMillion,
                completion: price?.completionPerMillion,
                intelligence: aa?.intelligence,
                costPerTask: aa?.costPerTaskUSD,
                userTokens: used.tokens
            )
        }

        // 3. Top OpenRouter global ranking LLMs
        for ranked in (openRouter?.rankings?.topModels ?? []).prefix(8) {
            guard raw.count < maxCount else { break }
            let price = prices[ranked.model] ?? normalizedPriceIndex[normalizedKey(ranked.model)]
            let aa = matchAA(forModelID: ranked.model, aaByNorm: aaByNorm)
            add(
                id: ranked.model,
                name: shortDisplayName(for: ranked.model),
                prompt: price?.promptPerMillion,
                completion: price?.completionPerMillion,
                intelligence: aa?.intelligence,
                costPerTask: aa?.costPerTaskUSD,
                userTokens: userTokensByModel[ranked.model.lowercased()]
            )
        }

        // 4. Fallback curated LLM spread (frontier / balanced / budget) when live pools are sparse
        if raw.count < min(4, maxCount) {
            for item in fallbackModels {
                guard raw.count < maxCount else { break }
                let price = prices[item.id] ?? normalizedPriceIndex[normalizedKey(item.id)]
                let aa = matchAA(forModelID: item.id, aaByNorm: aaByNorm)
                add(
                    id: item.id,
                    name: item.name,
                    prompt: price?.promptPerMillion ?? item.prompt,
                    completion: price?.completionPerMillion ?? item.completion,
                    intelligence: aa?.intelligence ?? (artificialAnalysis == nil ? item.intelligence : nil),
                    costPerTask: aa?.costPerTaskUSD,
                    userTokens: userTokensByModel[item.id.lowercased()]
                )
            }
        }

        let limited = Array(raw.prefix(maxCount))
        var usedKeys = Set<String>()
        return limited.enumerated().map { index, item in
            let blended = blendedPrice(item.prompt, item.completion)
            let cheapness = blended.map { cheapnessScore(forBlendedPerMillion: $0) }
            var key = sanitizeChoiceKey(item.id)
            if key.isEmpty || usedKeys.contains(key) { key = "model_\(index + 1)" }
            usedKeys.insert(key)
            return JevModelCandidate(
                key: key,
                modelID: item.id,
                displayName: item.name,
                promptPerMillion: item.prompt,
                completionPerMillion: item.completion,
                intelligence: item.intelligence,
                costPerTaskUSD: item.costPerTask,
                cheapnessScore: cheapness,
                userTokens: item.userTokens
            )
        }
    }

    private static func matchPrice(
        forName name: String,
        prices: [String: OpenRouterModelPrice],
        normalizedIndex: [String: OpenRouterModelPrice]
    ) -> OpenRouterModelPrice? {
        let target = ArtificialAnalysisParser.normalizedName(name)
        guard !target.isEmpty else { return nil }
        if let exact = normalizedIndex[target] { return exact }
        return prices.values.first { price in
            guard isEligibleLLM(modelID: price.id) else { return false }
            let tail = price.id.split(separator: "/").last.map(String.init) ?? price.id
            let normTail = ArtificialAnalysisParser.normalizedName(tail)
            return !normTail.isEmpty && (target.contains(normTail) || normTail.contains(target))
        }
    }

    private static func matchAA(
        forModelID modelID: String,
        aaByNorm: [String: ArtificialAnalysisModel]
    ) -> ArtificialAnalysisModel? {
        let tail = modelID.split(separator: "/").last.map(String.init) ?? modelID
        let normTail = ArtificialAnalysisParser.normalizedName(tail)
        guard !normTail.isEmpty else { return nil }
        if let exact = aaByNorm[normTail] { return exact }
        return aaByNorm.first { key, _ in key.contains(normTail) || normTail.contains(key) }?.value
    }

    private static func normalizedKey(_ value: String) -> String {
        ArtificialAnalysisParser.normalizedName(value.split(separator: "/").last.map(String.init) ?? value)
    }

    static func sanitizeChoiceKey(_ value: String) -> String {
        let allowed = value.lowercased().map { ch -> Character in
            (ch.isASCII && (ch.isLetter || ch.isNumber)) ? ch : "_"
        }
        let collapsed = String(allowed)
            .split(separator: "_")
            .joined(separator: "_")
        return String(collapsed.prefix(48))
    }

    private static func shortDisplayName(for modelID: String) -> String {
        let raw = modelID.split(separator: "/").last.map(String.init) ?? modelID
        return raw.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

enum JevClassifierParser {
    static let defaultModel = "typesafe/jev-1.14"

    static func requestBody(for context: JevUsageContext, model: String? = nil) -> JSON {
        let resolvedModel = model ?? context.config.resolvedJevModel
        let weights = context.config.normalizedWeights
        var preferences: JSON = [
            "pricing_weight": Int((weights.pricing * 100).rounded()),
            "cheapness_weight": Int((weights.cheapness * 100).rounded()),
            "intelligence_weight": Int((weights.intelligence * 100).rounded()),
            "token_usage_weight": Int((weights.tokenUsage * 100).rounded())
        ]
        if let cap = context.config.maxBlendedPriceUSD {
            preferences["max_blended_price_per_1m_usd"] = cap
        }

        var usageState: JSON = [
            "total_tokens_30d": context.totalTokens30d,
            "active_providers": context.activeProviders
        ]
        if let spend = context.openRouterSpend30dUSD { usageState["openrouter_spend_30d_usd"] = round(spend * 100) / 100 }
        if let credits = context.openRouterCreditsRemainingUSD { usageState["credits_remaining_usd"] = round(credits * 100) / 100 }
        if let blended = context.blendedCostPerMillionUSD { usageState["blended_cost_per_million_usd"] = round(blended * 1000) / 1000 }
        if let cache = context.cacheHitRatePercent { usageState["cache_hit_rate_percent"] = round(cache * 10) / 10 }
        if let reasoning = context.reasoningSharePercent { usageState["reasoning_share_percent"] = round(reasoning * 10) / 10 }
        if let quota = context.lowestQuotaRemainingPercent { usageState["lowest_quota_remaining_percent"] = round(quota) }
        if !context.topUsedModels.isEmpty {
            usageState["top_used_models"] = context.topUsedModels.map { item -> JSON in
                ["model": item.model, "tokens": item.tokens, "spend_usd": round(item.spendUSD * 100) / 100]
            }
        }

        let candidateState: [JSON] = context.candidates.map { candidate in
            var row: JSON = [
                "key": candidate.key,
                "model_id": candidate.modelID,
                "name": candidate.displayName
            ]
            if let prompt = candidate.promptPerMillion { row["prompt_per_1m_usd"] = round(prompt * 1000) / 1000 }
            if let completion = candidate.completionPerMillion { row["completion_per_1m_usd"] = round(completion * 1000) / 1000 }
            if let intelligence = candidate.intelligence { row["intelligence_index"] = round(intelligence * 10) / 10 }
            if let taskCost = candidate.costPerTaskUSD { row["cost_per_task_usd"] = round(taskCost * 100) / 100 }
            if let cheapness = candidate.cheapnessScore { row["cheapness_score"] = Int(cheapness) }
            if let tokens = candidate.userTokens { row["user_tokens_30d"] = tokens }
            return row
        }

        var modelCriteria: [String: String] = [:]
        for candidate in context.candidates {
            var parts = [candidate.displayName, candidate.priceLabel]
            if let intel = candidate.intelligence { parts.append(String(format: "intelligence %.0f", intel)) }
            if let cheap = candidate.cheapnessScore { parts.append("cheapness \(Int(cheap))/100") }
            modelCriteria[candidate.key] = parts.joined(separator: " · ")
        }

        let state: JSON = [
            "task": context.task.isEmpty ? "General daily coding and AI workload based on current usage profile" : context.task,
            "preferences": preferences,
            "current_usage": usageState,
            "candidate_llms": candidateState
        ]

        let weightSummary = "pricing \(Int((weights.pricing * 100).rounded()))%, cheapness \(Int((weights.cheapness * 100).rounded()))%, intelligence \(Int((weights.intelligence * 100).rounded()))%, token usage \(Int((weights.tokenUsage * 100).rounded()))%"

        let questions: JSON = [
            "recommended_model": [
                "type": "choice",
                "instructions": "Select the single best generative LLM from candidate_llms according to the user's configured weights (\(weightSummary)), pricing, cheapness, intelligence, and current token usage/quota.",
                "criteria": modelCriteria
            ],
            "tier": [
                "type": "choice",
                "instructions": "Classify the optimal LLM tier for the user's configured weights (\(weightSummary)), current token usage, and task.",
                "criteria": [
                    "budget": "Ultra-cheap, high-volume or simple tasks where low token cost dominates",
                    "balanced": "Best intelligence-per-dollar sweet spot for everyday coding and analysis",
                    "frontier": "Maximum intelligence needed despite higher pricing and token burn"
                ]
            ],
            "spend_efficiency": [
                "type": "score",
                "instructions": "Rate how cost-efficient the user's current token usage and LLM pricing are.",
                "criteria": [
                    "Overpaying for current token volume",
                    "Room to optimize model spend",
                    "Well balanced cost vs intelligence",
                    "Highly cost-efficient usage"
                ]
            ],
            "cheapness_priority": [
                "type": "noul",
                "instructions": "Should the user prioritize cheaper LLMs right now given their configured weights, current token usage, remaining credits/quota, and task?",
                "criteria": [
                    "true": "High token burn, tight credits or quota, high cheapness weight, or simple task warrants a cheaper LLM",
                    "false": "Sufficient headroom, high intelligence weight, or task complexity justifies prioritizing higher intelligence"
                ]
            ]
        ]

        return [
            "model": resolvedModel,
            "state": state,
            "questions": questions
        ]
    }

    static func parse(_ raw: JSON, context: JevUsageContext, now: Date = Date()) throws -> JevClassificationResult {
        guard let answers = raw["answers"] as? JSON else { throw JevClassifierError.invalidResponse }
        guard let modelAnswer = answers["recommended_model"] as? JSON,
              let chosenKey = string(modelAnswer["choice"]) else {
            throw JevClassifierError.invalidResponse
        }

        let candidatesByKey = Dictionary(context.candidates.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let recommended = candidatesByKey[chosenKey]
        let modelConfidence = number(modelAnswer["confidence"]) ?? 0

        let rawModelProbs = modelAnswer["probabilities"] as? JSON ?? [:]
        let modelProbabilities: [(candidate: JevModelCandidate?, key: String, probability: Double)] = rawModelProbs
            .compactMap { key, value in
                guard let prob = number(value) else { return nil }
                return (candidate: candidatesByKey[key], key: key, probability: prob)
            }
            .sorted { $0.probability > $1.probability }

        let tierAnswer = answers["tier"] as? JSON ?? [:]
        let tierRaw = (string(tierAnswer["choice"]) ?? "balanced").lowercased()
        let tier = JevModelTier(rawValue: tierRaw) ?? .balanced
        let tierConfidence = number(tierAnswer["confidence"]) ?? 0

        let efficiencyAnswer = answers["spend_efficiency"] as? JSON ?? [:]
        let efficiencyScore = Int((number(efficiencyAnswer["score"]) ?? 2).rounded())
        let legendList = efficiencyAnswer["legend"] as? [String] ?? [
            "Overpaying for current token volume",
            "Room to optimize model spend",
            "Well balanced cost vs intelligence",
            "Highly cost-efficient usage"
        ]
        let clampedIndex = max(0, min(legendList.count - 1, efficiencyScore))
        let legendMap = efficiencyAnswer["legend"] as? [String: String]
        let efficiencyLegend = legendMap?[String(efficiencyScore)] ?? (legendList.isEmpty ? "Balanced" : legendList[clampedIndex])
        let efficiencyConfidence = number(efficiencyAnswer["confidence"]) ?? 0

        let cheapAnswer = answers["cheapness_priority"] as? JSON ?? [:]
        let cheapProb = max(0, min(1, number(cheapAnswer["noul"]) ?? 0.5))

        let usage = raw["usage"] as? JSON ?? [:]
        let inputTokens = Int((number(usage["input_tokens"]) ?? 0).rounded())
        let outputTokens = Int((number(usage["output_tokens"]) ?? 0).rounded())
        let costUSD = number(usage["cost"])

        return JevClassificationResult(
            requestID: string(raw["id"]),
            jevModel: string(raw["model"]) ?? context.config.resolvedJevModel,
            provider: string(raw["provider"]) ?? "OpenRouter",
            recommendedCandidate: recommended,
            recommendedKey: chosenKey,
            modelConfidence: modelConfidence,
            modelProbabilities: modelProbabilities,
            tier: tier,
            tierConfidence: tierConfidence,
            spendEfficiencyScore: efficiencyScore,
            spendEfficiencyLegend: efficiencyLegend,
            spendEfficiencyConfidence: efficiencyConfidence,
            prioritizeCheapnessProbability: cheapProb,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUSD: costUSD,
            context: context,
            classifiedAt: now
        )
    }
}

final class JevClassifierClient {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func classify(context: JevUsageContext, apiKey: String, now: Date = Date()) async throws -> JevClassificationResult {
        guard !context.candidates.isEmpty else { throw JevClassifierError.invalidResponse }
        let url = URL(string: "https://openrouter.ai/api/alpha/decisions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BurndownBar", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: JevClassifierParser.requestBody(for: context))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JevClassifierError.invalidResponse }
        let parsed = (try? JSONSerialization.jsonObject(with: data)) as? JSON

        switch http.statusCode {
        case 200...299:
            guard let parsed else { throw JevClassifierError.invalidResponse }
            return try JevClassifierParser.parse(parsed, context: context, now: now)
        case 401, 403:
            throw JevClassifierError.unauthorized
        case 402:
            throw JevClassifierError.insufficientCredits
        case 429:
            throw JevClassifierError.rateLimited
        default:
            let detail = string((parsed?["error"] as? JSON)?["message"]) ?? string(parsed?["message"])
            throw JevClassifierError.unavailable(http.statusCode, detail)
        }
    }
}
