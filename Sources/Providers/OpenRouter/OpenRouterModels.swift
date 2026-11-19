import Foundation

struct OpenRouterKeySummary: Identifiable {
    let hash: String
    var name: String
    var label: String?
    var usageUSD: Double
    var byokUsageUSD: Double
    var limitUSD: Double?
    var limitRemainingUSD: Double?
    var limitReset: String?
    var disabled: Bool
    var expiresAt: Date?
    var spend30dUSD: Double?
    var tokens30d: Int64?
    var cacheHitRate: Double?

    var id: String { hash }
    var displayName: String {
        if !name.isEmpty { return name }
        if let label, !label.isEmpty { return label }
        return String(hash.prefix(8))
    }
}

struct OpenRouterModelSummary: Identifiable {
    let model: String
    var requests: Int
    var spendUSD: Double
    var tokens: Int64
    var reasoningTokens: Int64
    var cachedTokens: Int64
    var cacheHitRate: Double?
    var p50LatencyMs: Double?
    var p90LatencyMs: Double?

    var id: String { model }
}

struct OpenRouterEndpointHealth: Identifiable {
    let model: String
    let providerName: String
    var status: String
    var uptimeLast30m: Double?
    var promptPricePerMillion: Double?
    var completionPricePerMillion: Double?

    var id: String { "\(model)::\(providerName)" }
    var isHealthy: Bool {
        let lower = status.lowercased()
        if lower == "down" || lower == "degraded" || lower == "offline" { return false }
        if let uptime = uptimeLast30m, uptime < 95 { return false }
        return true
    }
}

struct OpenRouterGuardrail: Identifiable {
    let id: String
    var name: String
    var limitUSD: Double?
    var resetInterval: String?
    var enforceZDR: Bool
    var allowedModels: [String]
    var keyHashes: [String]
}

struct OpenRouterModelPrice {
    let id: String
    let promptPerMillion: Double
    let completionPerMillion: Double
    let cacheReadPerMillion: Double?
    let contextLength: Int?
}

struct OpenRouterGlobalModelRank: Identifiable {
    let model: String
    let totalTokens: Int64
    let sharePercent: Double?
    let changePercent: Double?
    var id: String { model }
}

enum OpenRouterRankingPeriod: String, CaseIterable, Identifiable {
    case today, week, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        }
    }
    var days: Int {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        }
    }
}

struct OpenRouterGlobalAppRank: Identifiable {
    let rank: Int
    let name: String
    let totalTokens: Int64
    let requests: Int?
    var id: String { "\(rank)-\(name)" }
}

struct OpenRouterTaskShare: Identifiable {
    let name: String
    let tokenSharePercent: Double
    let usageSharePercent: Double
    var id: String { name }
}

struct OpenRouterRankingsSnapshot {
    var asOf: String?
    var topModels: [OpenRouterGlobalModelRank] = []
    var modelPeriods: [OpenRouterRankingPeriod: [OpenRouterGlobalModelRank]] = [:]
    var topApps: [OpenRouterGlobalAppRank] = []
    var taskShares: [OpenRouterTaskShare] = []

    func models(for period: OpenRouterRankingPeriod) -> [OpenRouterGlobalModelRank] {
        modelPeriods[period] ?? (period == .week ? topModels : [])
    }

    var isEmpty: Bool { topModels.isEmpty && topApps.isEmpty && taskShares.isEmpty }
}

struct OpenRouterSnapshot {
    var isManagementKey: Bool
    var hasStandardKey: Bool = false
    var creditsTotalUSD: Double?
    var creditsUsedUSD: Double?
    var creditsRemainingUSD: Double?
    var byokSpend30dUSD: Double?
    var reasoningTokens30d: Int64 = 0
    var outputTokens30d: Int64 = 0
    var cacheHitRate: Double?
    var possibleCacheHitRate: Double?
    var blendedCostPerMillion: Double?
    var keySeries: [UsageSeries] = []
    var keys: [OpenRouterKeySummary] = []
    var models: [OpenRouterModelSummary] = []
    var endpoints: [OpenRouterEndpointHealth] = []
    var guardrails: [OpenRouterGuardrail] = []
    var rankings: OpenRouterRankingsSnapshot?
    var statusMessage: String?

    var reasoningSharePercent: Double? {
        let total = outputTokens30d + reasoningTokens30d
        guard total > 0, reasoningTokens30d > 0 else { return nil }
        return Double(reasoningTokens30d) / Double(total) * 100
    }

    var primaryZDRGuardrail: OpenRouterGuardrail? {
        guardrails.first(where: \.enforceZDR) ?? guardrails.first
    }
}
