import Foundation

enum JevClassifierTests {
    static func run() -> Int {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
            passed += 1
        }

        var openRouterAccount = Account(
            id: "or-1", name: "OpenRouter", email: "dev@example.com",
            provider: "openrouter", authIndex: "", accountID: nil,
            disabled: false, plan: "Credits", origin: .openrouter
        )
        openRouterAccount.updatedAt = Date()
        openRouterAccount.openRouter = OpenRouterSnapshot(
            isManagementKey: true,
            hasStandardKey: true,
            creditsTotalUSD: 50,
            creditsUsedUSD: 38,
            creditsRemainingUSD: 12,
            blendedCostPerMillion: 4.5,
            models: [
                OpenRouterModelSummary(model: "typesafe/jev-1.14", requests: 40, spendUSD: 0.01, tokens: 200_000, reasoningTokens: 0, cachedTokens: 0),
                OpenRouterModelSummary(model: "anthropic/claude-sonnet-4", requests: 120, spendUSD: 28, tokens: 4_500_000, reasoningTokens: 400_000, cachedTokens: 1_000_000),
                OpenRouterModelSummary(model: "openai/text-embedding-3-large", requests: 10, spendUSD: 0.2, tokens: 100_000, reasoningTokens: 0, cachedTokens: 0)
            ],
            rankings: OpenRouterRankingsSnapshot(
                asOf: "2026-11-19",
                topModels: [
                    OpenRouterGlobalModelRank(model: "typesafe/jev-1.14", totalTokens: 5_000_000, sharePercent: 5, changePercent: nil),
                    OpenRouterGlobalModelRank(model: "openrouter/auto", totalTokens: 4_000_000, sharePercent: 4, changePercent: nil),
                    OpenRouterGlobalModelRank(model: "google/gemini-2.5-flash", totalTokens: 9_000_000, sharePercent: 12, changePercent: nil)
                ]
            )
        )

        let aaSnapshot = ArtificialAnalysisSnapshot(
            models: [
                ArtificialAnalysisModel(id: "aa-1", name: "Claude Sonnet 4", creator: "Anthropic", intelligence: 61, minutesPerTask: 14.0, costPerTaskUSD: 11.2),
                ArtificialAnalysisModel(id: "aa-2", name: "Gemini 2.5 Flash", creator: "Google", intelligence: 52, minutesPerTask: 4.5, costPerTaskUSD: 0.9)
            ],
            tier: "free",
            fetchedAt: Date(),
            timeFromPublicLeaderboard: true
        )

        let prices: [String: OpenRouterModelPrice] = [
            "typesafe/jev-1.14": OpenRouterModelPrice(id: "typesafe/jev-1.14", promptPerMillion: 0.042, completionPerMillion: 0.0, cacheReadPerMillion: nil, contextLength: 262_144),
            "anthropic/claude-sonnet-4": OpenRouterModelPrice(id: "anthropic/claude-sonnet-4", promptPerMillion: 3.0, completionPerMillion: 15.0, cacheReadPerMillion: 0.3, contextLength: 200_000),
            "google/gemini-2.5-flash": OpenRouterModelPrice(id: "google/gemini-2.5-flash", promptPerMillion: 0.15, completionPerMillion: 0.60, cacheReadPerMillion: 0.03, contextLength: 1_000_000)
        ]

        var config = JevClassifierConfig()
        config.jevModel = "typesafe/jev-1.13"
        config.pricingWeight = 0.4
        config.cheapnessWeight = 0.4
        config.intelligenceWeight = 0.1
        config.tokenUsageWeight = 0.1
        config.excludedModels = "deepseek"

        let context = JevContextBuilder.build(
            accounts: [openRouterAccount],
            localUsage: [:],
            artificialAnalysis: aaSnapshot,
            prices: prices,
            task: "Classify and summarize daily CI logs",
            config: config
        )
        check(context.totalTokens30d == 4_800_000, "Jev context aggregates 30d token usage")
        check(!context.candidates.contains(where: { $0.modelID.lowercased().contains("jev") }),
              "Jev classifier models are excluded from candidate LLM results")
        check(JevClassifierConfig.presets.allSatisfy { !JevContextBuilder.isEligibleLLM(modelID: $0.id) },
              "Decision classifier presets cannot be recommended as generative LLMs")
        check(!context.candidates.contains(where: { $0.modelID.lowercased().contains("embedding") || $0.modelID.lowercased().contains("openrouter/auto") }),
              "Non-LLM models and routers are excluded from candidate LLM results")
        check(!context.candidates.contains(where: { $0.modelID.lowercased().contains("deepseek") }),
              "User-excluded models are filtered out of candidates")
        check(context.cheapestCandidate?.modelID == "google/gemini-2.5-flash", "Jev context identifies cheapest LLM from pricing")
        check(context.highestIntelligenceCandidate?.intelligence == 61, "Jev context retains Artificial Analysis intelligence index")

        let sonnet = context.candidates.first(where: { $0.modelID == "anthropic/claude-sonnet-4" })!
        let flash = context.candidates.first(where: { $0.modelID == "google/gemini-2.5-flash" })!
        check((sonnet.cheapnessScore ?? 100) < 50 && (flash.cheapnessScore ?? 0) > 75,
              "Cheapness score uses realistic log pricing scale instead of inflating expensive models to 100")

        var cappedConfig = JevClassifierConfig()
        cappedConfig.maxBlendedPriceUSD = 1.0
        let cappedContext = JevContextBuilder.build(
            accounts: [openRouterAccount],
            localUsage: [:],
            artificialAnalysis: aaSnapshot,
            prices: prices,
            task: "",
            config: cappedConfig
        )
        check(cappedContext.candidates.allSatisfy { ($0.blendedPerMillion ?? 0) <= 1.0 },
              "Max blended price cap filters out LLMs above the configured budget")

        let response: JSON = [
            "id": "gen-dec-test",
            "model": "typesafe/jev-1.13",
            "provider": "TypeSafe",
            "answers": [
                "recommended_model": [
                    "type": "choice",
                    "choice": flash.key,
                    "probabilities": [flash.key: 0.82, sonnet.key: 0.18],
                    "confidence": 0.88
                ],
                "tier": [
                    "type": "choice",
                    "choice": "budget",
                    "confidence": 0.91
                ],
                "spend_efficiency": [
                    "type": "score",
                    "score": 1,
                    "legend": ["Overpaying for current token volume", "Room to optimize model spend", "Well balanced cost vs intelligence", "Highly cost-efficient usage"],
                    "confidence": 0.84
                ],
                "cheapness_priority": [
                    "type": "noul",
                    "noul": 0.86
                ]
            ],
            "usage": [
                "input_tokens": 310,
                "output_tokens": 0,
                "cost": 0.000013
            ]
        ]

        do {
            let result = try JevClassifierParser.parse(response, context: context)
            check(result.recommendedCandidate?.modelID == "google/gemini-2.5-flash", "Jev parser resolves recommended LLM")
            check(result.tier == .budget && result.spendEfficiencyScore == 1 && result.spendEfficiencyLegend == "Room to optimize model spend",
                  "Jev parser extracts tier and spend efficiency score")
            check(abs(result.prioritizeCheapnessProbability - 0.86) < 0.001 && result.inputTokens == 310,
                  "Jev parser extracts noul probability and usage")
            var mappedResponse = response
            var mappedAnswers = response["answers"] as! JSON
            mappedAnswers["spend_efficiency"] = [
                "score": 1.8, "legend": ["0": "Poor", "1": "Fair", "2": "Good", "3": "Excellent"],
                "confidence": 0.84
            ]
            mappedResponse["answers"] = mappedAnswers
            let mappedResult = try JevClassifierParser.parse(mappedResponse, context: context)
            check(mappedResult.spendEfficiencyScore == 2 && mappedResult.spendEfficiencyLegend == "Good",
                  "Decision score uses its provider-supplied indexed legend")
        } catch {
            fputs("FAIL: Jev parser threw \(error)\n", stderr); exit(1)
        }

        return passed
    }
}
