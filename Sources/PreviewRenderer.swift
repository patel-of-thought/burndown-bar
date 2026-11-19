import AppKit
import SwiftUI

// These are explicit design fixtures; live dashboard data is never replaced with them.
@MainActor enum PreviewRenderer {
    static func run() {
        _ = NSApplication.shared
        let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("previews")
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let now = Date()
        let cursorWindows = [QuotaWindow(id: "total", title: "Total", remaining: 93, reset: now.addingTimeInterval(13 * 86400 + 7 * 3600), period: 30 * 86400),
            QuotaWindow(id: "cursor", title: "Cursor", remaining: 94, reset: now.addingTimeInterval(13 * 86400 + 7 * 3600), period: 30 * 86400),
            QuotaWindow(id: "api", title: "Third Party", remaining: 70, reset: now.addingTimeInterval(13 * 86400 + 7 * 3600), period: 30 * 86400),
            QuotaWindow(id: "grok", title: "Grok Bot", remaining: 55, reset: now.addingTimeInterval(3 * 86400 + 3 * 3600), period: 7 * 86400)]
        var cursor = SubscriptionClient.placeholder(.cursor)
        let dailyFixtures: [DailyUsage] = (0..<30).map { index in
            let weight = Double(1 + (index * 7) % 5 + (index % 3 == 0 ? 2 : 0))
            return DailyUsage(date: Calendar.current.date(byAdding: .day, value: index - 29, to: Calendar.current.startOfDay(for: now))!,
                              dollars: weight * 1.9, input: Int64(weight * 90_000), output: Int64(weight * 60_000),
                              cacheRead: Int64(weight * 2_400_000), cacheWrite: Int64(weight * 380_000))
        }
        cursor = Account(id: cursor.id, name: "Cursor", email: "Preview · example account", provider: "cursor", authIndex: "", accountID: nil,
            disabled: false, plan: "Pro", windows: cursorWindows, updatedAt: now, origin: .cursor,
            details: ProviderDetails(source: "Cursor.app", version: "Preview", status: "All Systems Operational", statusIndicator: "none"),
            costs: UsageCosts(today: CostPeriod(dollars: 4.21, tokens: 12_000_000), last30Days: CostPeriod(dollars: 249.08, tokens: 485_000_000), updatedAt: now, daily: dailyFixtures))

        var factory = SubscriptionClient.placeholder(.factory)
        factory.windows = [QuotaWindow(id: "5h", title: "5-hour", remaining: 96, reset: now.addingTimeInterval(7080), period: 18000),
            QuotaWindow(id: "weekly", title: "Weekly", remaining: 97, reset: now.addingTimeInterval(6 * 86400 + 7 * 3600), period: 604800),
            QuotaWindow(id: "monthly", title: "Monthly", remaining: 98, reset: now.addingTimeInterval(29 * 86400 + 7 * 3600), period: 2592000)]
        factory.plan = "Factory Team_Annual – Fallback: droidCore"
        factory.updatedAt = now
        factory.details = ProviderDetails(source: "API key · Keychain", version: "Preview", status: "Partial System Outage", statusIndicator: "minor", extraBalanceUSD: 0)

        let openRouter = Account(
            id: "direct-openrouter", name: "OpenRouter", email: "OpenRouter Account", provider: "openrouter",
            authIndex: "", accountID: nil, disabled: false, plan: "Pay-as-you-go · 3 active keys",
            windows: [
                QuotaWindow(id: "or-credits", title: "Account credits", remaining: 68, reset: nil, period: nil),
                QuotaWindow(id: "or-key", title: "Key: cursor-agent", remaining: 54, reset: now.addingTimeInterval(3 * 86400 + 11 * 3600), period: 604800)
            ],
            credits: "$68.40", updatedAt: now, origin: .openrouter,
            details: ProviderDetails(source: "OpenRouter Management + Standard Keys", extraBalanceUSD: 68.40, dashboardURL: URL(string: AccountOrigin.openrouter.dashboard)),
            costs: UsageCosts(today: CostPeriod(dollars: 2.85, tokens: 4_120_000), last30Days: CostPeriod(dollars: 64.10, tokens: 96_800_000), updatedAt: now,
                              daily: dailyFixtures.map { var d = $0; d.cacheWrite = 0; d.dollars *= 0.48; return d }),
            facts: [
                UsageFact(label: "Cache hit", value: "66.4% hit · 82.1% cacheable"),
                UsageFact(label: "Reasoning", value: "18.2% of output (1.4M)"),
                UsageFact(label: "Blended rate", value: "$0.66 / 1M"),
                UsageFact(label: "30d requests", value: "4.8K")
            ],
            openRouter: OpenRouterSnapshot(
                isManagementKey: true, hasStandardKey: true, creditsTotalUSD: 100, creditsUsedUSD: 31.60, creditsRemainingUSD: 68.40,
                cacheHitRate: 66.4, possibleCacheHitRate: 82.1, blendedCostPerMillion: 0.66,
                keys: [
                    OpenRouterKeySummary(hash: "k1", name: "cursor-agent", usageUSD: 28.40, byokUsageUSD: 0, limitUSD: 50, limitRemainingUSD: 21.60, limitReset: "weekly", disabled: false, spend30dUSD: 28.40, cacheHitRate: 69),
                    OpenRouterKeySummary(hash: "k2", name: "opencode-cli", usageUSD: 22.10, byokUsageUSD: 0, limitUSD: 40, limitRemainingUSD: 17.90, limitReset: "monthly", disabled: false, spend30dUSD: 22.10, cacheHitRate: 61),
                    OpenRouterKeySummary(hash: "k3", name: "zed-inline", usageUSD: 13.60, byokUsageUSD: 0, limitUSD: nil, limitRemainingUSD: nil, limitReset: nil, disabled: false, spend30dUSD: 13.60, cacheHitRate: 74)
                ],
                models: [
                    OpenRouterModelSummary(model: "anthropic/claude-sonnet-4", requests: 2810, spendUSD: 38.20, tokens: 52_100_000, reasoningTokens: 900_000, cachedTokens: 35_400_000, cacheHitRate: 68, p90LatencyMs: 2100),
                    OpenRouterModelSummary(model: "openai/gpt-4o", requests: 1420, spendUSD: 17.90, tokens: 29_300_000, reasoningTokens: 0, cachedTokens: 18_100_000, cacheHitRate: 62, p90LatencyMs: 1400)
                ],
                endpoints: [
                    OpenRouterEndpointHealth(model: "anthropic/claude-sonnet-4", providerName: "Anthropic", status: "operational", uptimeLast30m: 99.9, promptPricePerMillion: 3.0, completionPricePerMillion: 15.0)
                ],
                guardrails: [OpenRouterGuardrail(id: "g1", name: "Strict ZDR", limitUSD: 100, resetInterval: "monthly", enforceZDR: true, allowedModels: [], keyHashes: ["k1", "k2"])],
                rankings: OpenRouterRankingsSnapshot(
                    asOf: "2026-11-18",
                    topModels: [
                        OpenRouterGlobalModelRank(model: "anthropic/claude-sonnet-4", totalTokens: 142_000_000_000, sharePercent: 24.5, changePercent: 12.4),
                        OpenRouterGlobalModelRank(model: "openai/gpt-4o", totalTokens: 98_500_000_000, sharePercent: 17.0, changePercent: -2.1)
                    ],
                    topApps: [OpenRouterGlobalAppRank(rank: 1, name: "OpenCode", totalTokens: 82_000_000_000, requests: 910_000)],
                    taskShares: [OpenRouterTaskShare(name: "code-generation", tokenSharePercent: 34.2, usageSharePercent: 31.0)]
                ),
                statusMessage: "$2.14/day avg · ~32d runway"
            )
        )
        let accounts = [openRouter, cursor, factory]

        if let costs = cursor.costs {
            let eventSeries = UsageSeries(id: "usage-events", title: "Cursor usage events", daily: costs.daily, hasCost: true)
            let proxySeries = UsageSeries(id: "proxy-requests", title: ProxyUsageReader.requestsTitle,
                                          daily: costs.daily.map { var day = $0; day.dollars = 0; return day }, hasCost: false)
            let fixtures: [(String, [UsageSeries], UsageChart.Metric, UsageChart.Style)] = [
                ("cursor-tokens", [eventSeries], .tokens, .bars),
                ("codex-tokens", [proxySeries, eventSeries.localCopy], .tokens, .bars),
                ("codex-pie", [proxySeries, eventSeries.localCopy], .tokens, .pie)
            ]
            for (name, series, metric, style) in fixtures {
                let chart = UsageChart(series: series, tint: .orange, metric: metric, style: style).padding(16).frame(width: 398)
                    .background(Color(nsColor: .windowBackgroundColor))
                render(chart, to: output.appendingPathComponent("\(name)-preview.png"))
            }
        }

        let overviewStore = DashboardStore(persistPreferences: false)
        overviewStore.accounts = accounts; overviewStore.tab = "Overview"; overviewStore.now = now; overviewStore.lastRefresh = now; overviewStore.privacy = false
        render(Dashboard(store: overviewStore, expanded: true), to: output.appendingPathComponent("overview-preview.png"))

        for account in accounts {
            let store = DashboardStore(persistPreferences: false)
            store.accounts = accounts; store.select(account); store.now = now; store.lastRefresh = now; store.privacy = false
            render(Dashboard(store: store, expanded: true), to: output.appendingPathComponent("\(account.providerName.lowercased())-preview.png"))
        }

        let rankingsStore = DashboardStore(persistPreferences: false)
        rankingsStore.accounts = accounts; rankingsStore.selectSection(.rankings); rankingsStore.now = now; rankingsStore.lastRefresh = now; rankingsStore.privacy = false
        render(Dashboard(store: rankingsStore, expanded: true), to: output.appendingPathComponent("rankings-preview.png"))

        let analysisStore = DashboardStore(persistPreferences: false)
        analysisStore.artificialAnalysis = ArtificialAnalysisSnapshot(models: [
            ArtificialAnalysisModel(id: "a", name: "Claude Fable 5.2", creator: "Anthropic", intelligence: 65, minutesPerTask: 41.2, costPerTaskUSD: 26.54),
            ArtificialAnalysisModel(id: "b", name: "GPT-6.2 Astra", creator: "OpenAI", intelligence: 62, minutesPerTask: 13.7, costPerTaskUSD: 4.0),
            ArtificialAnalysisModel(id: "c", name: "Gemini 4 Neon", creator: "Google", intelligence: 61, minutesPerTask: 21.5, costPerTaskUSD: 6.44)
        ], tier: "free", fetchedAt: now, timeFromPublicLeaderboard: true)
        render(ArtificialAnalysisChartsView(store: analysisStore).frame(width: 398).padding(12),
               to: output.appendingPathComponent("artificial-analysis-charts-preview.png"))

        let settings = DashboardStore(persistPreferences: false)
        settings.accounts = accounts; settings.now = now; settings.settingsVisible = true
        settings.connectionProvider = .openrouter
        for (name, store) in [("settings", settings),
                              ("openrouter-connection", connectionPreview(openRouter, accounts: accounts)),
                              ("cursor-connection", connectionPreview(cursor, accounts: accounts))] {
            render(Dashboard(store: store, expanded: true), to: output.appendingPathComponent("\(name)-preview.png"))
        }
    }

    private static func render<V: View>(_ view: V, to path: URL) {
        let styled = view.environment(\.colorScheme, .dark)
        let hosting = NSHostingView(rootView: styled)
        hosting.appearance = NSAppearance(named: .darkAqua)
        let fitting = hosting.fittingSize
        let size = NSSize(width: max(398, fitting.width), height: max(120, fitting.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor.windowBackgroundColor
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: path)
                print(path.path)
                return
            }
        }
        let renderer = ImageRenderer(content: styled)
        renderer.scale = 2
        if let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? data.write(to: path)
            print(path.path)
        }
    }

    private static func connectionPreview(_ account: Account, accounts: [Account]) -> DashboardStore {
        let store = DashboardStore(persistPreferences: false)
        store.accounts = accounts
        store.connectionProvider = account.origin
        store.cursorSource = "browser"
        store.connectionVisible = true
        return store
    }
}

private extension UsageSeries {
    var localCopy: UsageSeries { UsageSeries(id: "agent-logs", title: ProxyUsageReader.agentLogsTitle, daily: daily, hasCost: false) }
}
