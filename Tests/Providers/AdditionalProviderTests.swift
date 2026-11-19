import Foundation

enum AdditionalProviderTests {
    static func run() -> Int {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fputs("FAIL: \(label)\n", stderr); exit(1) }; checks += 1
        }
        func rejected(_ label: String, _ operation: () throws -> Void) {
            do { try operation(); check(false, label) } catch { check(true, label) }
        }
        let now = date("2026-11-15T12:00:00Z")!
        let copilot = try! AdditionalParsers.copilot(["copilot_plan": "individual", "quota_reset_date": "2026-12-01", "quota_snapshots": [
            "premium_interactions": ["percent_remaining": 90, "entitlement": 300, "remaining": 270],
            "chat": ["unlimited": true]]], now: now)
        check(copilot.windows.first?.title == "Premium" && copilot.windows.first?.remaining == 90, "Copilot premium quota")
        check(copilot.windows.first?.reset == date("2026-12-01T00:00:00Z"), "Copilot date-only reset")
        check(copilot.windows.count == 1 && copilot.facts.contains { $0.value == "Unlimited" }, "Copilot unlimited chat is a fact, not a fake bar")
        let metered = try! AdditionalParsers.copilot(["token_based_billing": true, "quota_snapshots": ["premium_interactions": ["entitlement": 0, "remaining": 0, "percent_remaining": 100, "credits_used": 15]]])
        check(metered.windows.isEmpty && metered.facts.contains { $0.value == "15" }, "Copilot placeholder quota preserves real credit usage")
        let legacy = try! AdditionalParsers.copilot(["monthly_quotas": ["completions": 100], "limited_user_quotas": ["completions": 75]])
        check(legacy.windows.first?.remaining == 75, "Copilot legacy fallback")
        rejected("Copilot ended subscription rejected") { _ = try AdditionalParsers.copilot(["access_type_sku": "subscription_ended"]) }
        rejected("Copilot malformed response rejected") { _ = try AdditionalParsers.copilot([:]) }

        let warpUser: JSON = [
            "requestLimitInfo": ["isUnlimited": false, "requestLimit": 100, "requestsUsedSinceLastRefresh": 20, "nextRefreshTime": "2026-12-01T00:00:00Z"],
            "bonusGrants": [["requestCreditsGranted": 20, "requestCreditsRemaining": 10, "expiration": "2026-12-01T00:00:00Z"]],
            "workspaces": [["bonusGrantsInfo": ["grants": [["requestCreditsGranted": 10, "requestCreditsRemaining": 5]]]]]]
        let warpJSON: JSON = ["data": ["user": ["__typename": "UserOutput", "user": warpUser]]]
        let warp = try! AdditionalParsers.warp(warpJSON, now: now)
        check(warp.windows.first?.remaining == 80 && warp.windows.last?.remaining == 50, "Warp AI and combined bonus allowance")
        check(warp.windows.last?.reset == nil && warp.facts.contains { $0.label == "Next bonus expiry" }, "bonus expiry is not a recurring reset")
        let warpUnlimited = try! AdditionalParsers.warp(["data": ["user": ["user": ["requestLimitInfo": ["isUnlimited": true]]]]])
        check(warpUnlimited.windows.isEmpty && warpUnlimited.facts.first?.value == "Unlimited", "Warp unlimited has no invented ceiling")
        rejected("Warp GraphQL errors rejected") { _ = try AdditionalParsers.warp(["errors": [["message": "Unauthorized"]]]) }
        rejected("Warp missing limits rejected") { _ = try AdditionalParsers.warp(["data": ["user": ["user": [:]]]]) }

        let zed = try! AdditionalParsers.zed(["user": ["id": 123, "github_login": "fixture"], "plan": ["plan_v3": "zed_pro", "has_overdue_invoices": false,
            "usage": ["edit_predictions": ["used": 100, "limit": ["limited": 1000]]],
            "subscription_period": ["started_at": "2026-11-01T00:00:00Z", "ended_at": "2026-12-01T00:00:00Z"]]], now: now)
        check(zed.windows.first?.remaining == 90 && zed.email == "fixture", "Zed editor quota and identity")
        check(zed.windows.first?.period == 30 * 86400 && zed.windows.first?.reset == date("2026-12-01T00:00:00Z"), "Zed quota uses actual billing cycle")
        let zedWeb = try! AdditionalParsers.zed(["plan": "zed_pro", "current_usage": ["edit_predictions": ["used": 200, "limit": "unlimited"],
            "token_spend": ["spend_in_cents": 1250, "limit_in_cents": 5000]]], web: true)
        check(zedWeb.windows.count == 1 && zedWeb.windows.first?.title == "Token budget" && zedWeb.windows.first?.remaining == 75, "Zed web token-spend budget")
        check(zedWeb.facts.contains { $0.value.contains("12.50") }, "Zed token spend converts cents to USD")
        rejected("Zed malformed response rejected") { _ = try AdditionalParsers.zed([:]) }

        let open = try! AdditionalParsers.openCode(["usage": ["rolling": ["usagePercent": 0.5, "resetInSec": 1000],
            "weekly": ["used": 30, "limit": 100, "resetAt": "2026-11-20T00:00:00Z"]]], now: now)
        check(open.windows.first?.remaining == 99.5 && open.windows.last?.remaining == 70, "OpenCode API percentage units and used/limit")
        check(open.windows.first?.reset == now.addingTimeInterval(1000), "OpenCode relative reset")
        let console = try! AdditionalParsers.openCode(["access": ["endsAt": "2026-12-01T00:00:00Z", "meters": [
            "fiveHour": ["usagePercent": 0.5], "month": ["usedMicroCents": 30, "limitMicroCents": 100]]]], console: true)
        check(console.windows.first?.remaining == 50 && console.windows.last?.remaining == 70, "OpenCode Console fractions differ from API percentages")
        check(console.windows.last?.reset == date("2026-12-01T00:00:00Z"), "OpenCode month falls back to subscription end")
        rejected("OpenCode missing meters rejected") { _ = try AdditionalParsers.openCode(["access": NSNull()], console: true) }

        let ag = try! AdditionalParsers.antigravity(["summary": ["groups": [["displayName": "Gemini", "buckets": [
            ["bucketId": "weekly", "displayName": "Weekly", "remaining": ["case": "remainingFraction", "value": 0.75], "window": "weekly", "resetTime": "2026-11-20T00:00:00Z"],
            ["bucketId": "disabled", "displayName": "Daily", "disabled": true, "remainingFraction": 1]]]]]], now: now)
        check(ag.windows.count == 2 && ag.windows.first?.remaining == 75 && ag.windows.last?.remaining == nil, "Antigravity summary and disabled buckets")
        check(ag.windows.first?.period == 604800 && ag.windows.first?.title == "Gemini · Weekly", "Antigravity quota cadence")
        let agOld = try! AdditionalParsers.antigravity(["userStatus": ["email": "fixture@example.test", "cascadeModelConfigData": ["clientModelConfigs": [
            ["label": "Claude", "quotaInfo": ["remainingFraction": 0.9, "resetTime": "2026-11-20T00:00:00Z"]]]]]])
        check(agOld.email == "fixture@example.test" && agOld.windows.first?.remaining == 90, "Antigravity model-quota fallback")
        rejected("Antigravity error code rejected") { _ = try AdditionalParsers.antigravity(["code": "unauthorized", "groups": []]) }

        let uid = getuid()
        let own = "\(uid) 100 1 /Applications/Antigravity.app/Contents/Resources/language_server_macos_arm --csrf_token=abc --extension_server_port 5999"
        let ignored = "\(uid) 101 1 /Applications/Cursor.app/language_server --csrf_token no"
        let monitor = "\(uid) 200 1 /Applications/CodexBar.app/Contents/MacOS/CodexBar"
        let monitorChild = "\(uid) 201 200 /Applications/Antigravity.app/Contents/Resources/language_server --csrf_token=ignore"
        let processes = LocalAntigravityProcess.parse([own, ignored, monitor, monitorChild].joined(separator: "\n"))
        check(processes.count == 1 && processes[0].pid == 100 && processes[0].csrf == "abc", "local Antigravity excludes other apps and CodexBar-owned sessions")
        check(processes.first?.extensionPort == 5999, "local Antigravity flag parsing")
        check(AntigravityLocalClient.ports("p100\nn127.0.0.1:5999\nn*:6000\nn/other/file") == [5999,6000], "local API ports are process scoped")
        check(LocalAntigravityProcess.parse(own, uid: uid + 1).isEmpty, "other users' processes are excluded")
        func cookie(_ domain: String, expiry: Date? = nil) -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [.domain: domain, .path: "/", .name: "session", .value: "fixture"]
            if let expiry { properties[.expires] = expiry }
            return HTTPCookie(properties: properties)!
        }
        let header = ProviderCookiePolicy.header([cookie(".opencode.ai"), cookie("opencode.ai.evil.test"), cookie("github.com"), cookie("opencode.ai", expiry: now.addingTimeInterval(-1))], origin: .opencode, now: now)
        check(header == "session=fixture", "browser sign-in filters foreign and expired cookies")
        check(ProviderCookiePolicy.header([cookie("example.test")], origin: .zed) == nil, "no matching cookie is not a successful sign-in")
        check(!SubscriptionClient.safeID("../escape") && !SubscriptionClient.safeID("abc?token=x") && SubscriptionClient.safeID("org_fixture-1"), "workspace IDs cannot escape the API path")
        check(SubscriptionClient.safeSlug("claude-3.5-sonnet:free") && !SubscriptionClient.safeSlug("../evil"), "model slugs allow colons/dots but reject traversal")

        let orStd = try! AdditionalParsers.openRouterStandardKey(["data": [
            "label": "cursor-key", "limit": 20.0, "limit_remaining": 15.0, "limit_reset": "weekly",
            "usage": 5.0, "usage_daily": 1.25, "usage_weekly": 5.0, "usage_monthly": 5.0, "byok_usage": 0.5
        ]], now: now)
        check(orStd.windows.first?.remaining == 75 && orStd.windows.first?.period == 604800, "OpenRouter standard key weekly limit")
        check(orStd.costs?.today.dollars == 1.25 && orStd.openRouter?.isManagementKey == false, "OpenRouter standard key costs and mode")
        rejected("OpenRouter malformed key rejected") { _ = try AdditionalParsers.openRouterStandardKey([:]) }

        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let orMgmt = try! AdditionalParsers.openRouterManagement(
            creditsJSON: ["data": ["total_credits": 100.0, "total_usage": 40.0]],
            keysJSON: ["data": [
                ["hash": "key_1", "name": "cursor-agent", "usage": 12.0, "limit": 20.0, "limit_remaining": 8.0, "limit_reset": "daily", "disabled": false],
                ["hash": "key_2", "name": "paused-key", "usage": 5.0, "limit": 10.0, "limit_remaining": 1.0, "disabled": true]
            ]],
            analyticsDailyJSON: ["data": ["data": [
                ["date__day": "2026-11-15T00:00:00Z", "request_count": 10, "total_usage": 2.5, "prompt_tokens": 1000, "completion_tokens": 200, "reasoning_tokens": 50, "cached_tokens": 400, "cache_hit_rate": 0.4, "possible_cache_hit_rate": 0.7]
            ]]],
            analyticsByKeyJSON: ["data": ["data": [
                ["date__day": "2026-11-15T00:00:00Z", "api_key": "key_1", "total_usage": 2.5, "prompt_tokens": 1000, "completion_tokens": 200, "reasoning_tokens": 50, "cached_tokens": 400]
            ]]],
            analyticsByModelJSON: ["data": ["data": [
                ["model": "anthropic/claude-sonnet-4", "request_count": 10, "total_usage": 2.5, "prompt_tokens": 1000, "completion_tokens": 200, "reasoning_tokens": 50, "cached_tokens": 400, "p90_latency": 1200]
            ]]],
            guardrailsJSON: ["data": [["id": "gr-1", "name": "Strict ZDR", "limit_usd": 50, "reset_interval": "monthly", "enforce_zdr": true]]],
            now: now,
            calendar: utc
        )
        check(orMgmt.windows.count == 2 && orMgmt.windows.first?.remaining == 60 && orMgmt.windows.last?.remaining == 40, "OpenRouter credits and tightest active key cap (ignores disabled)")
        check(orMgmt.costs?.today.dollars == 2.5 && orMgmt.costs?.today.tokens == 1250, "OpenRouter 30d analytics splits cached tokens without double-counting")
        check(orMgmt.openRouter?.keySeries.first?.title == "Key: cursor-agent", "OpenRouter per-key chart series mapping")
        check(orMgmt.openRouter?.models.first?.p90LatencyMs == 1200 && orMgmt.openRouter?.primaryZDRGuardrail?.enforceZDR == true, "OpenRouter model latency and guardrail parsing")

        let orEndpoints = AdditionalParsers.openRouterEndpoints(["data": ["endpoints": [
            ["provider_name": "Anthropic", "status": "operational", "uptime_last_30m": 0.995, "pricing": ["prompt": "0.000003", "completion": "0.000015"]]
        ]]], model: "anthropic/claude-sonnet-4")
        check(orEndpoints.first?.uptimeLast30m == 99.5 && abs((orEndpoints.first?.promptPricePerMillion ?? 0) - 3.0) < 0.001, "OpenRouter endpoint uptime and per-million pricing")

        let orRankings = AdditionalParsers.openRouterRankings(
            modelsJSON: ["meta": ["as_of": "2026-11-18T00:00:00Z"], "data": [
                ["date": "2026-11-18", "model_permaslug": "anthropic/claude-sonnet-4", "total_tokens": 700],
                ["date": "2026-11-18", "model_permaslug": "other", "total_tokens": 300]
            ]],
            appsJSON: ["data": [["rank": 1, "app_name": "OpenCode", "total_tokens": "500000", "total_requests": 100]]],
            tasksJSON: ["categories": [["category": "Code", "token_share": 0.42, "usage_share": 0.4, "classifications": [
                ["task": "code-generation", "token_share": 0.3, "usage_share": 0.25]
            ]]]]
        )
        check(orRankings?.topModels.count == 1 && orRankings?.topModels.first?.sharePercent == 70, "OpenRouter rankings excludes 'other' row from leaderboard while keeping total denominator")
        let periodRankings = AdditionalParsers.openRouterRankings(modelsJSON: ["meta": ["as_of": "2026-11-18T00:00:00Z"], "data": [
            ["date": "2026-11-17", "model_permaslug": "openai/current", "total_tokens": "9007199254740993"],
            ["date": "2026-11-16", "model_permaslug": "openai/previous", "total_tokens": "100"],
            ["date": "2026-11-10", "model_permaslug": "openai/previous", "total_tokens": "50"]
        ]], appsJSON: nil, tasksJSON: nil)
        check(periodRankings?.models(for: .today).first?.totalTokens == 9_007_199_254_740_993,
              "OpenRouter ranking token strings retain 64-bit precision")
        check(periodRankings?.models(for: .week).count == 2 && periodRankings?.models(for: .month).count == 2,
              "OpenRouter rankings aggregate daily rows into week and month leaderboards")
        check(orRankings?.topApps.first?.name == "OpenCode" && orRankings?.topApps.first?.totalTokens == 500_000, "OpenRouter stringified app token counts parsed")
        check(orRankings?.taskShares.first?.name == "code-generation" && orRankings?.taskShares.first?.tokenSharePercent == 30, "OpenRouter task share normalized to percent")

        // Direct Codex credential sources.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("burndown-codex-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func jwtToken(_ claims: JSON) -> String {
            func part(_ value: Any) -> String {
                (try! JSONSerialization.data(withJSONObject: value)).base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            }
            return [part(["alg": "none"]), part(claims), "sig"].joined(separator: ".")
        }
        let future = Date().timeIntervalSince1970 + 3600
        let authFile = root.appendingPathComponent("auth.json")
        func writeAuth(_ access: String) {
            let value: JSON = ["tokens": ["access_token": access, "id_token": jwtToken(["email": "file@example.test"])]]
            try? JSONSerialization.data(withJSONObject: value).write(to: authFile)
        }
        writeAuth(jwtToken(["exp": future, "https://api.openai.com/auth": ["chatgpt_account_id": "acct-file"]]))
        let fileCodex = try? SubscriptionCredentials.codex(authFile: authFile, keychain: { _ in nil }, environment: [:])
        check(fileCodex?.accountID == "acct-file" && fileCodex?.email == "file@example.test" && fileCodex?.source == "Codex CLI sign-in", "Codex CLI sign-in file is read")
        writeAuth(jwtToken(["exp": Date().timeIntervalSince1970 - 60]))
        check((try? SubscriptionCredentials.codex(authFile: authFile, keychain: { _ in nil }, environment: [:])) == nil, "expired Codex sign-in is rejected")
        check((try? SubscriptionCredentials.codex(authFile: root.appendingPathComponent("missing.json"), keychain: { _ in nil }, environment: [:])) == nil, "no Codex sign-in gives guidance")
        let keychainCodex = try? SubscriptionCredentials.codex(authFile: authFile, keychain: { $0 == "codex-key" ? "saved-token" : nil }, environment: [:])
        check(keychainCodex?.token == "saved-token" && keychainCodex?.source == "Access token · Keychain", "a saved Codex token wins over the CLI file")
        let envCodex = try? SubscriptionCredentials.codex(authFile: authFile, keychain: { _ in nil }, environment: ["CODEX_ACCESS_TOKEN": "from-env", "CODEX_ACCOUNT_ID": "acct-env"])
        check(envCodex?.token == "from-env" && envCodex?.accountID == "acct-env" && envCodex?.source == "Access token · environment", "Codex token from process environment")
        return checks
    }
}
