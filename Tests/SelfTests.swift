import Foundation

enum SelfTests {
    @MainActor static func run() {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
            passed += 1
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let windows = QuotaParser.codex(["rate_limit": [
            "primary_window": ["used_percent": 2, "reset_after_seconds": 600, "limit_window_seconds": 18000],
            "secondary_window": ["used_percent": 30, "reset_at": 1_800_200_000, "limit_window_seconds": 604800]
        ]], now: now)
        check(windows.count == 2, "both quota windows")
        check(windows.first?.remaining == 98, "remaining is inverse of usage")
        check(windows.last?.remaining == 70, "weekly remaining")
        check(windows.first?.reset == now.addingTimeInterval(600), "relative reset")
        check(windows.last?.reset == Date(timeIntervalSince1970: 1_800_200_000), "absolute reset")
        let missing = QuotaParser.codex(["rate_limit": ["secondary_window": ["reset_after_seconds": 10]]], now: now)
        check(missing.count == 1 && missing[0].remaining == nil, "missing percentage stays unknown")
        check(QuotaParser.codex([:]).isEmpty, "missing window is not invented")
        let extreme = QuotaParser.codex(["rate_limit": ["primary_window": ["used_percent": 120]]])
        check(extreme.first?.remaining == 0, "percentage clamped")
        check(number(true) == nil, "booleans are not quota values")
        let jsonNumbers = try! JSONSerialization.jsonObject(with: Data("{\"zero\":0,\"one\":1,\"boolean\":true}".utf8)) as! JSON
        check(number(jsonNumbers["zero"]) == 0 && number(jsonNumbers["one"]) == 1 && number(jsonNumbers["boolean"]) == nil,
              "JSON zero and one are numbers, not booleans")
        let monthly = QuotaParser.codex(["rate_limit": ["secondary_window": ["used_percent": 10, "limit_window_seconds": 2592000]]])
        check(monthly.first?.title == "Monthly", "monthly quota is labeled correctly")
        let claude = QuotaParser.claude(["five_hour": ["utilization": 25.5, "resets_at": "2026-11-15T21:00:00Z"]])
        check(claude.first?.remaining == 74.5 && claude.first?.reset != nil, "Claude response")
        let account = Account.parse(["name": "test.json", "auth_index": "abc", "type": "codex", "email": "test@example.com", "disabled": false])
        check(account?.providerName == "Codex" && account?.email == "test@example.com", "credential parsing")
        check(Account.parse(["name": "missing-index.json"]) == nil, "no requests without auth index")
        let config = try! ProxyConfiguration.parse("port = 8317\nmanagement-secret-key = \"test\\\"key\"\n[other]\nport = 1")
        check(config.port == 8317 && config.secret == "test\"key", "escaped configuration and root keys")
        let single = try! ProxyConfiguration.parse("management-secret-key = 'test-key'\nport = 9000 # comment")
        check(single.port == 9000 && single.secret == "test-key", "literal strings and numeric comments")
        do {
            _ = try ProxyConfiguration.parse("port = 8317")
            check(false, "missing key rejected")
        } catch { check(true, "missing key rejected") }
        check(duration(0) == "now" && duration(3660) == "1h 1m", "countdown formatting")
        let cursor = SubscriptionParser.cursor(summary: [
            "billingCycleStart": "2026-11-01T00:00:00Z", "billingCycleEnd": "2026-12-01T00:00:00Z",
            "individualUsage": ["plan": ["totalPercentUsed": 7, "autoPercentUsed": 6, "apiPercentUsed": 30]]
        ], sand: ["usagePercent": 45, "hasNonZeroIncludedLimit": true, "nextResetTimestampUtc": "2026-11-20T00:00:00Z"], now: now)
        check(cursor.map(\.title) == ["Total", "Cursor", "Third Party", "Grok Bot"], "Cursor breakdown and Grok Bot titles")
        check(cursor.map(\.remaining) == [93, 94, 70, 55], "Cursor breakdown uses percentage units")
        check(cursor.first?.period == 30 * 86400, "Cursor pace uses actual billing cycle")
        let fractional = SubscriptionParser.cursor(summary: ["individualUsage": ["plan": ["totalPercentUsed": 0.36]]], sand: nil)
        check(abs((fractional.first?.remaining ?? 0) - 99.64) < 0.0001, "fractional percent is not a 0-to-1 ratio")
        let unavailable = SubscriptionParser.cursor(summary: [:], sand: nil)
        check(unavailable.first?.remaining == nil, "unknown Cursor quota never defaults to full")
        let shared = SubscriptionParser.cursor(summary: [:], sand: ["isUnified": true, "usagePercent": 20,
            "hasNonZeroIncludedLimit": true, "nextResetTimestampUtc": now.addingTimeInterval(1000).timeIntervalSince1970], now: now)
        check(shared.count == 1 && shared.first?.title == "Weekly" && shared.first?.remaining == 80,
              "unified Cursor plans show their authoritative weekly pool")
        let trial = SubscriptionParser.cursor(summary: [:], sand: ["usagePercent": 20, "includedLimitZero": true,
            "sandTrialExpiresAt": now.addingTimeInterval(1000).timeIntervalSince1970], now: now)
        check(trial.last?.title == "Grok Bot" && trial.last?.reset == nil, "trial expiry is not a recurring reset")
        let limits: JSON = ["usesTokenRateLimitsBilling": true, "limits": ["standard": [
            "fiveHour": ["usedPercent": 4, "secondsRemaining": 7200],
            "weekly": ["usedPercent": 3, "secondsRemaining": 6 * 86400],
            "monthly": ["usedPercent": 2, "secondsRemaining": 29 * 86400]]]]
        let factory = try! SubscriptionParser.factory(limits: limits, now: now)
        check(factory.map(\.remaining) == [96, 97, 98], "Factory has 5-hour, weekly and monthly quotas")
        check(factory.map(\.period) == [18000, 604800, 2592000], "Factory quota periods")
        check(factory.first?.reset == now.addingTimeInterval(7200), "Factory seconds remaining reset")
        let expiredFactory = try! SubscriptionParser.factory(limits: ["usesTokenRateLimitsBilling": true, "limits": ["standard": [
            "fiveHour": ["usedPercent": 90, "windowEnd": now.addingTimeInterval(-1).timeIntervalSince1970]]]], now: now)
        check(expiredFactory.first?.remaining == 100 && expiredFactory.first?.reset == nil, "expired Factory rolling window is reset")
        let unknownFactory = try! SubscriptionParser.factory(limits: ["usesTokenRateLimitsBilling": true, "limits": ["standard": ["weekly": ["secondsRemaining": 1000]]]], now: now)
        check(unknownFactory.first?.remaining == nil, "missing Factory percentage stays unknown")
        do { _ = try SubscriptionParser.factory(limits: [:]); check(false, "invalid Factory response rejected") }
        catch { check(true, "invalid Factory response rejected") }
        let factoryPlan = SubscriptionParser.factoryPlan(["organization": ["subscription": ["factoryTier": "team", "orbSubscription": ["plan": ["name": "Team_Annual"]]]]], limits: ["overagePreference": "droidCore"])
        check(factoryPlan == "Factory Team – Team_Annual – Fallback: droidCore", "Factory plan and fallback")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let reportNow = date("2026-11-15T12:00:00Z")!
        func event(_ time: Date, cents: Any = 100) -> JSON {
            ["timestamp": String(Int64(time.timeIntervalSince1970 * 1000)),
             "tokenUsage": ["totalCents": cents, "inputTokens": 100, "outputTokens": 20, "cacheWriteTokens": 30, "cacheReadTokens": 50]]
        }
        let costs = SubscriptionParser.costs(events: [event(reportNow, cents: 421), event(reportNow.addingTimeInterval(-86400), cents: 200),
            event(reportNow.addingTimeInterval(-40 * 86400), cents: 999)], now: reportNow, calendar: utc)
        check(costs.today.dollars == 4.21 && costs.last30Days.dollars == 6.21, "today and 30-day cost boundaries; cents to dollars")
        check(costs.today.tokens == 200 && costs.last30Days.tokens == 400, "input, output and cache tokens counted")
        check(costs.today.isComplete && costs.last30Days.isComplete, "complete cost report")
        check(costs.daily.count == 30 && costs.daily.first?.date == utc.date(byAdding: .day, value: -29, to: utc.startOfDay(for: reportNow)),
              "daily series covers 30 consecutive days, oldest first")
        let lastDay = costs.daily.last, prevDay = costs.daily.dropLast().last
        check(lastDay?.dollars == 4.21 && prevDay?.dollars == 2, "daily cost per calendar day")
        check(lastDay.map { [$0.input, $0.output, $0.cacheRead, $0.cacheWrite] } == [100, 20, 50, 30], "daily input, output, cache read and cache write tokens")
        check(costs.daily.reduce(0, { $0 + $1.dollars }) == costs.last30Days.dollars && costs.daily.reduce(0, { $0 + $1.tokens }) == costs.last30Days.tokens,
              "daily series adds up to the 30-day totals")
        check(costs.daily.dropLast(2).allSatisfy { $0.dollars == 0 && $0.tokens == 0 }, "days without usage stay zero")
        let partial = SubscriptionParser.costs(events: [event(reportNow, cents: NSNull())], now: reportNow, calendar: utc)
        check(partial.today.dollars == nil && !partial.today.isComplete && partial.today.tokens == 200, "unknown cost stays unavailable without hiding valid tokens")
        let badDate = SubscriptionParser.costs(events: [["error": "invalid"]], now: reportNow, calendar: utc)
        check(badDate.today.dollars == nil && badDate.last30Days.tokens == nil && !badDate.last30Days.isComplete, "malformed events cannot imply zero usage")
        let zero = SubscriptionParser.costs(events: [], now: reportNow, calendar: utc)
        check(zero.today.dollars == 0 && zero.last30Days.tokens == 0 && zero.today.isComplete, "confirmed empty usage is zero")
        let emptyPage = try! CursorEventPage([:])
        check(emptyPage.total == 0 && emptyPage.events.isEmpty, "confirmed empty API page")
        do { _ = try CursorEventPage(["error": "bad request"]); check(false, "error envelope rejected") }
        catch { check(true, "error envelope rejected") }
        let a: JSON = ["timestamp": 1], b: JSON = ["timestamp": 2], c: JSON = ["timestamp": 3]
        var paging = CursorPagination(pageSize: 2)
        let page1 = try! paging.append(CursorEventPage(["totalUsageEventsCount": 3, "usageEventsDisplay": [a,b]]))
        check(!page1, "full usage page continues pagination")
        let page2 = try! paging.append(CursorEventPage(["totalUsageEventsCount": 3, "usageEventsDisplay": [b,c]]))
        let page3 = try! paging.append(CursorEventPage(["totalUsageEventsCount": 3, "usageEventsDisplay": []]))
        check(!page2 && page3 && paging.events.count == 3, "adjacent page overlap is not double-counted")
        do {
            var repeated = CursorPagination(pageSize: 2)
            _ = try repeated.append(CursorEventPage(["usageEventsDisplay": [a,b]]))
            _ = try repeated.append(CursorEventPage(["usageEventsDisplay": [a,b]]))
            check(false, "repeated pages rejected")
        } catch { check(true, "repeated pages rejected") }
        do {
            var incomplete = CursorPagination(pageSize: 1000)
            _ = try incomplete.append(CursorEventPage(["totalUsageEventsCount": 9, "usageEventsDisplay": [a,b]]))
            check(false, "truncated report rejected")
        } catch { check(true, "truncated report rejected") }
        do {
            var changing = CursorPagination(pageSize: 2)
            _ = try changing.append(CursorEventPage(["totalUsageEventsCount": 4, "usageEventsDisplay": [a,b]]))
            _ = try changing.append(CursorEventPage(["totalUsageEventsCount": 5, "usageEventsDisplay": [c]]))
            check(false, "changing report totals rejected")
        } catch { check(true, "changing report totals rejected") }
        let grok = GrokBilling.parse([["currentPeriod": ["type": "weekly", "start": "2026-11-15T00:00:00Z", "end": "2026-11-22T00:00:00Z"],
            "creditUsagePercent": 12.5, "productUsage": [["product": "Grok Build", "usagePercent": 25]], "prepaidBalance": ["val": "1200"]]])
        check(grok.windows.map(\.remaining) == [87.5, 75], "Grok weekly credits and product quotas")
        check(grok.windows.first?.period == 604800 && grok.balanceUSD == 12, "Grok reset window and wrapped cents")
        let grokMonthly = GrokBilling.parse([["monthlyLimit": ["val": "15000"], "used": ["val": "18000"],
            "onDemandCap": 10000, "billingPeriodStart": "2026-11-01T00:00:00Z", "billingPeriodEnd": "2026-12-01T00:00:00Z"]])
        check(grokMonthly.windows.first?.remaining == 0 && grokMonthly.windows.last?.remaining == 70, "Grok monthly allowance and derived overage")
        check(grokMonthly.plan == "SuperGrok", "Grok recognized allowance tier")
        check(GrokBilling.parse([[:]]).windows.isEmpty, "missing Grok billing is never fabricated")
        let grokUnknown = GrokBilling.parse([["current_period": ["type": "weekly"]]])
        check(grokUnknown.windows.first?.remaining == nil, "missing Grok percent stays unknown")
        let grokMerge = GrokBilling.parse([["current_period": ["type": "weekly"]], ["creditUsagePercent": 5]])
        check(grokMerge.windows.count == 1 && grokMerge.windows.first?.remaining == 95, "Grok billing response merge fills missing data")
        check(Account.parse(["auth_index": "grok-test", "type": "xai", "metadata": ["user_id": "user-123"]])?.providerUserID == "user-123", "Grok user ID metadata")
        let routing = DashboardStore(persistPreferences: false)
        routing.cursorEnabled = true
        routing.droidEnabled = true
        routing.additionalEnabled = [:]
        routing.quotaSources = ["default": "proxy"]
        check(AccountOrigin.proxyCapable.allSatisfy { routing.usesProxy($0) && !routing.usesDirect($0) },
              "proxy mode defaults compatible providers to CLIProxyAPI")
        check(routing.usesDirect(.antigravity) && !routing.usesProxy(.antigravity)
              && routing.quotaSource(for: .antigravity) == .direct,
              "Antigravity always uses its local connection")
        check(routing.usesDirect(.cursor) && routing.usesDirect(.factory) && !routing.usesProxy(.cursor),
              "proxy mode preserves independent provider connections")
        routing.setQuotaSource(.direct, for: .claude)
        check(routing.usesDirect(.claude) && !routing.usesProxy(.claude)
              && routing.usesProxy(.codex) && routing.usesProxy(.grok),
              "proxy mode allows a direct choice for one provider")
        routing.setQuotaSource(.direct)
        check(AccountOrigin.proxyCapable.allSatisfy { routing.usesDirect($0) && !routing.usesProxy($0) },
              "direct mode routes every compatible provider independently")
        routing.setQuotaSource(.proxy, for: .grok)
        check(!routing.usesProxy(.grok) && routing.quotaSources["grok"] == nil,
              "provider source controls do not change direct mode")
        routing.setQuotaSource(.proxy)
        check(routing.usesDirect(.claude) && routing.usesProxy(.codex) && routing.usesProxy(.grok),
              "provider choice survives switching away from proxy mode")
        routing.setQuotaSource(.proxy, for: .claude)
        check(routing.usesProxy(.claude) && routing.quotaSources["claude"] == nil,
              "restoring provider proxy choice removes its override")
        routing.additionalEnabled["claude"] = false
        check(!routing.usesDirect(.claude) && !routing.usesProxy(.claude), "hidden providers stay hidden with granular routing")
        routing.quotaSources = [:]
        check(routing.sharedQuotaSource == .proxy, "shared source defaults to CLIProxyAPI")
        check(QuotaSource.proxy.title == "CLIProxyAPI", "shared source uses the shorter display name")
        routing.settingsVisible = true
        routing.openConnectionSettings(.claude)
        check(routing.connectionVisible && !routing.settingsVisible && routing.connectionProvider == .claude,
              "Preferences opens the selected provider connection")
        check(!routing.isEnabled(.claude), "opening connection settings does not enable a hidden provider")
        routing.closeConnectionSettings()
        check(routing.settingsVisible && !routing.connectionVisible, "connection back navigation returns to Preferences")
        routing.settingsVisible = false
        routing.openConnectionSettings(.cursor)
        routing.closeConnectionSettings()
        check(!routing.settingsVisible && !routing.connectionVisible, "connection opened from Usage returns to Usage")
        var connectedCursor = SubscriptionClient.placeholder(.cursor)
        connectedCursor.updatedAt = Date()
        routing.accounts = [connectedCursor]
        check(routing.isProviderConnected(.cursor) && !routing.isProviderConnected(.factory),
              "provider status uses that provider's successfully fetched account")
        routing.accounts[0].error = "Session expired"
        check(!routing.isProviderConnected(.cursor), "failed account refresh clears the connected status")
        routing.accounts[0].error = nil
        routing.accounts[0].updatedAt = Date().addingTimeInterval(-601)
        check(!routing.isProviderConnected(.cursor), "stale accounts do not show a green connection dot")
        routing.accounts[0].updatedAt = nil
        check(!routing.isProviderConnected(.cursor), "unfetched placeholders do not show a green connection dot")
        var rankedSubscription = SubscriptionClient.placeholder(.cursor)
        rankedSubscription.windows = [QuotaWindow(id: "monthly", title: "Monthly", remaining: 35, reset: nil, period: nil)]
        rankedSubscription.updatedAt = Date()
        var rankedInference = SubscriptionClient.placeholder(.openrouter)
        rankedInference.windows = [QuotaWindow(id: "credits", title: "Credits", remaining: 80, reset: nil, period: nil)]
        rankedInference.updatedAt = Date()
        routing.accounts = [rankedSubscription, rankedInference]
        routing.selectSection(.subscriptions)
        check(routing.providers == ["Cursor"] && routing.sectionAccounts.count == 1, "subscription section excludes inference accounts")
        routing.selectSection(.inference)
        check(routing.providers == ["OpenRouter"] && routing.sectionAccounts.count == 1 && routing.tab == "Overview",
              "inference section shows OpenRouter and resets the provider tab")
        routing.selectSection(.rankings)
        check(routing.section == .rankings && routing.sectionAccounts.isEmpty,
              "global rankings section has no account tabs")
        routing.select(rankedInference)
        check(routing.section == .inference && routing.tab == "OpenRouter" && routing.selected?.id == rankedInference.id,
              "account selection opens its provider section")
        var connectedProxy = Account.parse(["auth_index": "status-fixture", "type": "codex"])!
        connectedProxy.updatedAt = Date()
        routing.accounts = [connectedProxy]
        check(routing.isProviderConnected(.codex), "proxy account status maps to its provider")
        routing.connectionError = "Proxy offline"
        check(!routing.isProviderConnected(.codex), "offline proxy clears its provider connection status")
        passed += AppIdentityTests.run()
        passed += AdditionalProviderTests.run()
        passed += BrowserCursorSessionTests.run()
        passed += ProxyUsageTests.run()
        passed += ArtificialAnalysisTests.run()
        if CommandLine.arguments.contains("--headless") {
            print("Skipped native provider icon sizing checks: graphical macOS session required.")
        } else { passed += ProviderLogoTests.run() }
        print("Passed \(passed) checks: proxy and direct-provider quotas, billing windows, costs, pagination, missing data and configuration.")
    }
}
