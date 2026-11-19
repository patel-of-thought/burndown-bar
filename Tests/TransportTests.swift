import Foundation

private final class FixtureURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Any))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unsupportedURL) }
            let (code, value) = try handler(request)
            let isHTML = value is Data
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": isHTML ? "text/html" : "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: isHTML ? value as! Data : try JSONSerialization.data(withJSONObject: value))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

enum TransportTests {
    static func run() async {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
            checks += 1
        }
        func configuration() -> URLSessionConfiguration {
            let value = URLSessionConfiguration.ephemeral
            value.protocolClasses = [FixtureURLProtocol.self]
            return value
        }
        let now = Date()
        FixtureURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v2/status.json": return (200, ["status": ["description": "All Systems Operational", "indicator": "none"]])
            case "/api/usage-summary":
                guard request.value(forHTTPHeaderField: "Cookie") == "WorkosCursorSessionToken=fixture" else { throw URLError(.userAuthenticationRequired) }
                return (200, ["membershipType": "pro", "billingCycleStart": "2026-11-01T00:00:00Z", "billingCycleEnd": "2026-12-01T00:00:00Z",
                    "individualUsage": ["plan": ["totalPercentUsed": 7, "autoPercentUsed": 6, "apiPercentUsed": 30]]])
            case "/api/auth/me": return (200, ["email": "fixture@example.test", "sub": "fixture-user"])
            case "/api/dashboard/get-sand-usage-status":
                guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Origin") == "https://cursor.com" else { throw URLError(.badServerResponse) }
                return (200, ["hasNonZeroIncludedLimit": true, "usagePercent": 45, "nextResetTimestampUtc": "2026-11-20T00:00:00Z"])
            case "/api/dashboard/get-filtered-usage-events":
                guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Origin") == "https://cursor.com" else { throw URLError(.badServerResponse) }
                return (200, ["totalUsageEventsCount": 1, "usageEventsDisplay": [["timestamp": String(Int64(now.timeIntervalSince1970 * 1000)),
                    "tokenUsage": ["totalCents": 421, "inputTokens": 100, "outputTokens": 20, "cacheReadTokens": 80]]]])
            case "/api/app/auth/me": return (200, ["userProfile": ["email": "factory@example.test", "id": "factory-fixture"],
                "organization": ["subscription": ["factoryTier": "team", "orbSubscription": ["plan": ["name": "Annual"]]]]])
            case "/api/billing/limits":
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer factory-fixture-key" else { throw URLError(.userAuthenticationRequired) }
                return (200, ["usesTokenRateLimitsBilling": true, "extraUsageBalanceCents": 1250, "overagePreference": "droidCore", "limits": ["standard": [
                    "fiveHour": ["usedPercent": 4, "secondsRemaining": 7080], "weekly": ["usedPercent": 3, "secondsRemaining": 543600],
                    "monthly": ["usedPercent": 2, "secondsRemaining": 2530800]]]])
            default: throw URLError(.unsupportedURL)
            }
        }
        do {
            let client = SubscriptionClient(configuration: configuration())
            let cursor = try await client.cursor(credentials: .init(cookie: "WorkosCursorSessionToken=fixture", source: "Test fixture", email: nil))
            check(cursor.windows.map(\.remaining) == [93,94,70,55], "Cursor authenticated API-to-dashboard integration")
            check(cursor.email == "fixture@example.test" && cursor.details?.source == "Test fixture", "Cursor identity and source")
            check(cursor.costs?.today.dollars == 4.21 && cursor.costs?.today.tokens == 200, "Cursor cost endpoint and units")
            check(cursor.details?.status == "All Systems Operational", "service status integration")
            let factory = try await client.factory(credentials: .init(token: "factory-fixture-key", source: "Test fixture"), detectVersion: false)
            check(factory.windows.map(\.remaining) == [96,97,98], "Factory bearer API-to-dashboard integration")
            check(factory.details?.extraBalanceUSD == 12.50 && factory.plan.contains("droidCore"), "Factory balance and fallback")
            check(factory.email == "factory@example.test" && factory.details?.statusIndicator == "none", "Factory identity and service status")
            do {
                _ = try await client.request(url: "https://example.com/usage", provider: "Test", headers: ["Authorization": "Bearer fixture"])
                check(false, "credentials restricted to provider endpoints")
            } catch { check(true, "credentials restricted to provider endpoints") }
            FixtureURLProtocol.handler = { _ in (401, ["error": "unauthorized"]) }
            do {
                _ = try await client.request(url: "https://cursor.com/api/usage-summary", provider: "Cursor")
                check(false, "expired session rejected")
            } catch SubscriptionError.unauthorized(let provider) { check(provider == "Cursor", "expired session gives reconnect guidance") }
            FixtureURLProtocol.handler = { _ in (302, [:]) }
            do {
                _ = try await client.request(url: "https://cursor.com/api/usage-summary", provider: "Cursor")
                check(false, "redirect is not accepted as usage")
            } catch SubscriptionError.http(let status) { check(status == 302, "redirect is not accepted as usage") }
            FixtureURLProtocol.handler = { request in
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-management-key" else { throw URLError(.userAuthenticationRequired) }
                switch request.url!.path {
                case "/v8/management/credentials": return (200, ["files": [["name": "codex-fixture", "type": "codex", "auth_index": "codex-index"]]])
                case "/v8/management/requests/api-call":
                    // Read either representation; URLSession may materialize POST data as a stream.
                    let data: Data
                    if let body = request.httpBody { data = body }
                    else if let stream = request.httpBodyStream {
                        stream.open(); defer { stream.close() }
                        var buffer = [UInt8](repeating: 0, count: 4096), collected = Data()
                        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; collected.append(buffer, count: count) }
                        data = collected
                    } else { throw URLError(.badServerResponse) }
                    let json = try JSONSerialization.jsonObject(with: data) as! JSON
                    let headers = json["header"] as! [String: String]
                    guard json["method"] as? String == "GET", json["url"] as? String == "https://chatgpt.com/backend-api/wham/usage",
                          headers["Authorization"] == "Bearer $TOKEN$" else { throw URLError(.badServerResponse) }
                    return (200, ["status_code": 200, "body": ["plan_type": "plus", "rate_limit": ["primary_window": ["used_percent": 20]], "credits": ["balance": 25]]])
                default: throw URLError(.unsupportedURL)
                }
            }
            let proxy = ProxyClient(config: .init(port: 8317, secret: "fixture-management-key"), configuration: configuration())
            let accounts = try await proxy.accounts()
            let codex = try await proxy.quota(for: accounts[0])
            check(codex.providerName == "Codex" && codex.windows.first?.remaining == 80, "Codex management API integration")
            check(codex.credits == "25" && codex.error == nil, "Codex balance through proxy")
            do {
                _ = try await proxy.quota(for: SubscriptionClient.placeholder(.cursor))
                check(false, "accounts the proxy does not serve are rejected")
            } catch { check(true, "accounts the proxy does not serve are rejected") }
            FixtureURLProtocol.handler = { request in
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-management-key" else { throw URLError(.userAuthenticationRequired) }
                if request.url!.path == "/v8/management/credentials" {
                    return (200, ["files": [
                        ["name": "xai.json", "type": "xai", "auth_index": "grok-index", "email": "grok@example.test"],
                        ["name": "claude.json", "type": "claude", "auth_index": "claude-index", "email": "claude@example.test"],
                        ["name": "ag.json", "type": "antigravity", "auth_index": "ag-index", "email": "ag@example.test"],
                        ["name": "gem.json", "type": "gemini", "auth_index": "gem-index"]]])
                }
                guard request.url!.path == "/v8/management/requests/api-call" else { throw URLError(.unsupportedURL) }
                let data: Data
                if let body = request.httpBody { data = body }
                else if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096), collected = Data()
                    while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; collected.append(buffer, count: count) }
                    data = collected
                } else { throw URLError(.badServerResponse) }
                let json = try JSONSerialization.jsonObject(with: data) as! JSON
                let headers = json["header"] as! [String: String]
                guard headers["Authorization"] == "Bearer $TOKEN$" else { throw URLError(.badServerResponse) }
                switch (json["authIndex"] as? String, json["url"] as? String) {
                case ("grok-index", "https://cli-chat-proxy.grok.com/v1/billing?format=credits"):
                    guard json["method"] as? String == "GET", headers["x-xai-token-auth"] == "xai-grok-cli" else { throw URLError(.badServerResponse) }
                    return (200, ["status_code": 200, "body": ["config": ["creditUsagePercent": 40, "currentPeriod": ["type": "USAGE_PERIOD_TYPE_WEEKLY"], "prepaidBalance": ["val": "500"]]]])
                case ("claude-index", "https://api.anthropic.com/api/oauth/usage"):
                    guard json["method"] as? String == "GET", headers["anthropic-beta"] == "oauth-2025-04-20" else { throw URLError(.badServerResponse) }
                    return (200, ["status_code": 200, "body": ["five_hour": ["utilization": 30, "resets_at": "2026-11-15T21:00:00Z"], "seven_day": ["utilization": 10]]])
                case ("claude-index", _), ("grok-index", _): throw URLError(.unsupportedURL)
                default: return (200, ["status_code": 401, "body": "expired"])
                }
            }
            let multi = try await proxy.accounts()
            check(multi.compactMap(\.proxyOrigin).count == 2 && multi.first { $0.provider == "gemini" }?.proxyOrigin == nil
                  && multi.first { $0.provider == "antigravity" }?.proxyOrigin == nil, "proxy credentials map only to supported providers")
            let grokProxy = try await proxy.quota(for: multi.first { $0.provider == "xai" }!)
            check(grokProxy.providerName == "Grok" && grokProxy.windows.first?.remaining == 60 && grokProxy.facts.first?.value == "$5.00", "Grok quota through the proxy")
            let claudeProxy = try await proxy.quota(for: multi.first { $0.provider == "claude" }!)
            check(claudeProxy.providerName == "Claude" && claudeProxy.windows.map(\.remaining) == [70, 90], "Claude quota through the proxy")
            do {
                _ = try await proxy.quota(for: multi.first { $0.authIndex == "ag-index" }!)
                check(false, "Antigravity proxy credentials are rejected")
            } catch { check(true, "Antigravity proxy credentials are rejected") }
            var wrongTarget = multi.first { $0.provider == "claude" }!
            wrongTarget = Account(id: "x", name: "x", email: "x", provider: "claude", authIndex: "other-index", accountID: nil, disabled: false, plan: "Subscription")
            do {
                _ = try await proxy.quota(for: wrongTarget)
                check(false, "expired proxy session is reported")
            } catch { check((error as? ProxyError)?.localizedDescription.contains("Reconnect") == true, "expired proxy session is reported") }
            FixtureURLProtocol.handler = { request in
                switch request.url!.path {
                case "/copilot_internal/user":
                    guard request.url?.host == "api.github.com", request.value(forHTTPHeaderField: "Authorization") == "token copilot-fixture" else { throw URLError(.userAuthenticationRequired) }
                    return (200, ["copilot_plan": "individual", "quota_snapshots": ["premium_interactions": ["percent_remaining": 80, "entitlement": 300, "remaining": 240]]])
                case "/user": return (200, ["login": "copilot-test", "id": 123])
                case "/graphql/v2":
                    guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Authorization") == "Bearer warp-fixture",
                          request.value(forHTTPHeaderField: "User-Agent") == "Warp/1.0", request.value(forHTTPHeaderField: "x-warp-client-id") == "warp-app" else { throw URLError(.badServerResponse) }
                    return (200, ["data": ["user": ["user": ["requestLimitInfo": ["isUnlimited": false, "requestLimit": 100, "requestsUsedSinceLastRefresh": 10]]]]])
                case "/client/users/me":
                    guard request.value(forHTTPHeaderField: "Authorization") == "zed-user zed-fixture" else { throw URLError(.userAuthenticationRequired) }
                    return (200, ["user": ["id": 12, "github_login": "zed-test"], "plan": ["plan_v3": "zed_pro", "usage": ["edit_predictions": ["used": 10, "limit": ["limited": 100]]]]])
                case "/frontend/billing/usage":
                    guard request.value(forHTTPHeaderField: "Cookie") == "zed=fixture" else { throw URLError(.userAuthenticationRequired) }
                    return (200, ["plan": "zed_pro", "current_usage": ["edit_predictions": ["used": 10, "limit": "unlimited"], "token_spend": ["spend_in_cents": 500, "limit_in_cents": 1000]]])
                case "/zen/go/v1/usage":
                    guard request.value(forHTTPHeaderField: "Authorization") == "Bearer opencode-fixture" else { throw URLError(.userAuthenticationRequired) }
                    return (200, ["usage": ["rolling": ["usagePercent": 10, "resetInSec": 3600], "weekly": ["usagePercent": 20]]])
                case "/console/api/orgs":
                    guard request.value(forHTTPHeaderField: "Cookie") == "opencode=fixture" else { throw URLError(.userAuthenticationRequired) }
                    return (200, [["id": "org_fixture"]])
                case "/console/api/go/status":
                    guard request.value(forHTTPHeaderField: "x-org-id") == "org_fixture", request.value(forHTTPHeaderField: "Cookie") == "opencode=fixture" else { throw URLError(.badServerResponse) }
                    return (200, ["access": ["meters": ["fiveHour": ["usagePercent": 0.25], "week": ["usagePercent": 0.5]]]])
                case "/api/organizations": return (200, [["uuid": "org-claude"]])
                case "/api/organizations/org-claude/usage":
                    guard request.value(forHTTPHeaderField: "Cookie") == "claude=fixture" else { throw URLError(.userAuthenticationRequired) }
                    return (200, ["five_hour": ["utilization": 20]])
                case "/v1/billing":
                    guard request.url?.host == "cli-chat-proxy.grok.com", request.value(forHTTPHeaderField: "Authorization") == "Bearer grok-fixture" else { throw URLError(.badServerResponse) }
                    return (200, ["config": ["creditUsagePercent": 35, "currentPeriod": ["type": "weekly"]]])
                case "/login/device/code":
                    guard request.url?.host == "github.com", request.httpMethod == "POST" else { throw URLError(.badServerResponse) }
                    return (200, ["device_code": "device-fixture", "user_code": "ABCD-EFGH", "expires_in": 900, "interval": 5])
                default: throw URLError(.unsupportedURL)
                }
            }
            let independent = SubscriptionClient(configuration: configuration())
            let copilot = try await independent.additional(.copilot, key: "copilot-fixture")
            check(copilot.windows.first?.remaining == 80 && copilot.email == "copilot-test" && copilot.origin == .copilot, "Copilot direct API and independent identity")
            let warp = try await independent.additional(.warp, key: "warp-fixture")
            check(warp.windows.first?.remaining == 90 && warp.origin == .warp, "Warp direct GraphQL credentials and client headers")
            let zed = try await independent.additional(.zed, zedAuthorization: "zed-user zed-fixture")
            check(zed.windows.first?.remaining == 90 && zed.email == "zed-test", "Zed editor authentication end to end")
            let zedWeb = try await independent.additional(.zed, cookie: "zed=fixture")
            check(zedWeb.windows.first?.remaining == 50 && zedWeb.origin == .zed, "Zed cookie billing end to end")
            let openCode = try await independent.additional(.opencode, key: "opencode-fixture")
            check(openCode.windows.map(\.remaining) == [90,80], "OpenCode Go direct key endpoint")
            let console = try await independent.additional(.opencode, cookie: "opencode=fixture", workspaceID: "org_fixture")
            check(console.windows.map(\.remaining) == [75,50] && console.facts.contains { $0.value == "org_fixture" }, "OpenCode independent Console session scoped to workspace")
            do {
                _ = try await independent.additional(.opencode, cookie: "opencode=fixture", workspaceID: "org_other")
                check(false, "inaccessible workspace never silently switches accounts")
            } catch { check(true, "inaccessible workspace never silently switches accounts") }
            let claude = try await independent.additional(.claude, cookie: "claude=fixture")
            check(claude.windows.first?.remaining == 80 && claude.origin == .claude, "Claude uses direct cookies rather than proxy")
            let directGrok = try await independent.additional(.grok, key: "grok-fixture")
            check(directGrok.windows.first?.remaining == 65 && directGrok.origin == .grok, "Grok uses direct bearer rather than proxy")
            let device = try await independent.githubDeviceCode()
            check(device.userCode == "ABCD-EFGH" && device.interval == 5 && device.expires == 900, "GitHub independent device-code request")
            do {
                _ = try await independent.githubPoll(.init(deviceCode: "expired", userCode: "", interval: 5, expires: 0))
                check(false, "expired device sign-in is bounded")
            } catch { check(true, "expired device sign-in is bounded") }
            FixtureURLProtocol.handler = { request in
                guard request.url?.host == "chatgpt.com", request.url?.path == "/backend-api/wham/usage",
                      request.value(forHTTPHeaderField: "Authorization") == "Bearer codex-fixture",
                      request.value(forHTTPHeaderField: "Chatgpt-Account-Id") == "acct-1" else { throw URLError(.badServerResponse) }
                return (200, ["plan_type": "pro", "rate_limit": ["primary_window": ["used_percent": 25]], "credits": ["unlimited": true]])
            }
            let directCodex = try await independent.additional(.codex, codex: .init(token: "codex-fixture", accountID: "acct-1", email: "codex@example.test", source: "Test"))
            check(directCodex.origin == .codex && directCodex.windows.first?.remaining == 75 && directCodex.email == "codex@example.test"
                  && directCodex.plan == "Pro" && directCodex.credits == "Unlimited", "Codex direct quota without the proxy")

            let isoNow = ISO8601DateFormatter().string(from: now)
            FixtureURLProtocol.handler = { request in
                let auth = request.value(forHTTPHeaderField: "Authorization")
                switch request.url!.path {
                case "/api/v1/credits":
                    if auth == "Bearer or-std-fixture" { return (403, ["error": "Only management keys"]) }
                    guard auth == "Bearer or-mgmt-fixture" else { return (401, ["error": "unauthorized"]) }
                    return (200, ["data": ["total_credits": 50.0, "total_usage": 10.0]])
                case "/api/v1/key":
                    guard auth == "Bearer or-std-fixture" else { return (401, ["error": "unauthorized"]) }
                    return (200, ["data": ["label": "std-key", "limit": 10.0, "limit_remaining": 7.0, "limit_reset": "daily", "usage": 3.0, "usage_daily": 1.0]])
                case "/api/v1/keys":
                    return (200, ["data": [["hash": "k1", "name": "opencode", "usage": 10.0, "limit": 25.0, "limit_remaining": 15.0, "limit_reset": "monthly", "disabled": false]]])
                case "/api/v1/analytics/meta":
                    return (200, ["data": ["metrics": []]])
                case "/api/v1/guardrails":
                    return (200, ["data": [["id": "g1", "name": "Prod ZDR", "enforce_zdr": true]]])
                case "/api/v1/analytics/query":
                    return (200, ["data": ["data": [
                        ["date__day": isoNow, "api_key": "k1", "model": "openai/gpt-4o", "request_count": 4, "total_usage": 1.25, "prompt_tokens": 500, "completion_tokens": 100, "reasoning_tokens": 0, "cached_tokens": 200]
                    ]]])
                case "/api/v1/models/openai/gpt-4o/endpoints":
                    return (200, ["data": ["endpoints": [["provider_name": "OpenAI", "status": "operational", "uptime_last_30m": 0.999, "pricing": ["prompt": "0.0000025", "completion": "0.00001"]]]]])
                case "/api/v1/models":
                    return (200, ["data": [["id": "openai/gpt-4o", "pricing": ["prompt": "0.0000025", "completion": "0.00001"]]]])
                case "/api/v1/datasets/rankings-daily":
                    guard auth == "Bearer or-std-fixture" else { return (403, ["error": "standard key required"]) }
                    return (200, ["meta": ["as_of": "2026-11-18T00:00:00Z"], "data": [["date": "2026-11-18", "model_permaslug": "openai/gpt-4o", "total_tokens": 1000]]])
                case "/api/v1/datasets/app-rankings":
                    guard auth == "Bearer or-std-fixture" else { return (403, ["error": "standard key required"]) }
                    return (200, ["data": [["rank": 1, "app_name": "Aider", "total_tokens": "2000"]]])
                default: throw URLError(.unsupportedURL)
                }
            }
            let orMgmt = try await independent.additional(.openrouter, key: "or-mgmt-fixture", standardKey: "or-std-fixture")
            check(orMgmt.origin == .openrouter && orMgmt.windows.first?.remaining == 80 && orMgmt.openRouter?.isManagementKey == true, "OpenRouter Management API integration")
            check(orMgmt.costs?.today.dollars == 1.25 && orMgmt.openRouter?.endpoints.first?.providerName == "OpenAI", "OpenRouter analytics and endpoint health transport")
            check(orMgmt.openRouter?.hasStandardKey == true && orMgmt.openRouter?.rankings?.topModels.first?.model == "openai/gpt-4o"
                  && orMgmt.openRouter?.rankings?.topApps.first?.name == "Aider", "OpenRouter dual-key fetches rankings via standard key alongside management key")
            let orStd = try await independent.additional(.openrouter, key: "or-std-fixture", standardKey: "or-std-fixture")
            check(orStd.openRouter?.isManagementKey == false && orStd.windows.first?.remaining == 70, "OpenRouter 403 falls back cleanly to standard key")

            var patchedLimit = false, toggledZDR = false
            FixtureURLProtocol.handler = { request in
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer or-mgmt-fixture" else { return (401, [:]) }
                if request.url!.path == "/api/v1/keys/k1" && request.httpMethod == "PATCH" {
                    patchedLimit = true
                    return (200, ["data": ["hash": "k1", "limit": 30]])
                }
                if request.url!.path == "/api/v1/guardrails/g1" && request.httpMethod == "PATCH" {
                    toggledZDR = true
                    return (200, ["data": ["id": "g1", "enforce_zdr": false]])
                }
                throw URLError(.unsupportedURL)
            }
            try await independent.updateOpenRouterKey(hash: "k1", limitUSD: 30, limitReset: "monthly", apiKey: "or-mgmt-fixture")
            try await independent.setOpenRouterZDR(enabled: false, guardrailID: "g1", keyHashes: ["k1"], apiKey: "or-mgmt-fixture")
            check(patchedLimit && toggledZDR, "OpenRouter key cap and ZDR guardrail PATCH mutations")

            var createdDisabled = false, assignedKeys = false, enabledAfterAssignment = false
            FixtureURLProtocol.handler = { request in
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer or-mgmt-fixture" else { return (401, [:]) }
                switch (request.url!.path, request.httpMethod ?? "") {
                case ("/api/v1/guardrails", "POST"):
                    let data = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
                        stream.open()
                        defer { stream.close() }
                        var data = Data()
                        var buffer = [UInt8](repeating: 0, count: 4096)
                        while stream.hasBytesAvailable {
                            let count = stream.read(&buffer, maxLength: buffer.count)
                            if count > 0 { data.append(buffer, count: count) } else { break }
                        }
                        return data
                    }
                    let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? JSON }
                    createdDisabled = body?["enforce_zdr"] as? Bool == false
                    return (200, ["data": ["id": "g2"]])
                case ("/api/v1/guardrails/g2/keys/bulk-assign", "POST"):
                    assignedKeys = createdDisabled
                    return (200, ["data": [:]])
                case ("/api/v1/guardrails/g2", "PATCH"):
                    enabledAfterAssignment = assignedKeys
                    return (200, ["data": ["id": "g2", "enforce_zdr": true]])
                default: throw URLError(.unsupportedURL)
                }
            }
            try await independent.setOpenRouterZDR(enabled: true, guardrailID: nil, keyHashes: ["k1"], apiKey: "or-mgmt-fixture")
            check(createdDisabled && assignedKeys && enabledAfterAssignment, "OpenRouter ZDR attaches keys before enabling a new guardrail")

            var patchedAfterFailure = false
            FixtureURLProtocol.handler = { request in
                if request.url!.path == "/api/v1/guardrails/g1/keys/bulk-assign" { return (500, [:]) }
                if request.url!.path == "/api/v1/guardrails/g1" { patchedAfterFailure = true; return (200, [:]) }
                throw URLError(.unsupportedURL)
            }
            var assignmentFailed = false
            do {
                try await independent.setOpenRouterZDR(enabled: true, guardrailID: "g1", keyHashes: ["k1"], apiKey: "or-mgmt-fixture")
            } catch { assignmentFailed = true }
            check(assignmentFailed && !patchedAfterFailure, "OpenRouter ZDR assignment failure prevents enforcement")
        } catch {
            fputs("FAIL: transport integration: \(error.localizedDescription)\n", stderr); exit(1)
        }
        FixtureURLProtocol.handler = { request in
            guard request.value(forHTTPHeaderField: "x-api-key") == "aa-free-fixture" || request.url!.path == "/leaderboards/models" else {
                return (401, ["error": "unauthorized"])
            }
            switch request.url!.path {
            case "/api/v2/language/models/free":
                let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value
                let row: JSON = ["id": page == "1" ? "one" : "two", "name": page == "1" ? "Claude Fable 5.2 (Max)" : "GPT-6.2 Astra (Max)",
                                 "model_creator": ["name": page == "1" ? "Anthropic" : "OpenAI"],
                                 "evaluations": ["artificial_analysis_intelligence_index": page == "1" ? 65 : 62],
                                 "artificial_analysis_intelligence_index_cost": ["cost_per_task": ["total_cost": page == "1" ? 26.54 : 4.0]]]
                return (200, ["tier": "free", "pagination": ["has_more": page == "1"], "data": [row]])
            case "/leaderboards/models":
                return (200, Data("<html><table><tbody><tr><td>Claude Fable 5.2 Max</td><td>65</td><td>$26.54</td><td>41.2</td></tr></tbody></table></html>".utf8))
            default: throw URLError(.unsupportedURL)
            }
        }
        do {
            let snapshot = try await ArtificialAnalysisClient(configuration: configuration()).rankings(key: "aa-free-fixture")
            check(snapshot.tier == "free" && snapshot.models.count == 2 && snapshot.topModels.first?.name.contains("Claude") == true,
                  "Artificial Analysis free API pagination and intelligence ordering")
            check(snapshot.timeFromPublicLeaderboard && snapshot.topModels.first?.minutesPerTask == 41.2,
                  "Artificial Analysis public leaderboard fills time per task for free keys")
        } catch {
            fputs("FAIL: Artificial Analysis transport: \(error.localizedDescription)\n", stderr); exit(1)
        }
        FixtureURLProtocol.handler = { request in
            guard request.url!.path == "/api/alpha/decisions",
                  request.httpMethod == "POST",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer or-std-fixture" else {
                return (401, ["error": ["message": "unauthorized"]])
            }
            let body = (request.httpBody ?? request.httpBodyStream.map { stream -> Data in
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count > 0 { data.append(buffer, count: count) } else { break }
                }
                return data
            }).flatMap { try? JSONSerialization.jsonObject(with: $0) as? JSON }
            let criteria = ((body?["questions"] as? JSON)?["recommended_model"] as? JSON)?["criteria"] as? [String: String]
            let firstKey = criteria?.keys.sorted().first ?? "model_1"
            return (200, [
                "id": "gen-dec-fixture",
                "model": "typesafe/jev-1.14",
                "provider": "TypeSafe",
                "answers": [
                    "recommended_model": ["type": "choice", "choice": firstKey, "probabilities": [firstKey: 0.91], "confidence": 0.91],
                    "tier": ["type": "choice", "choice": "balanced", "confidence": 0.87],
                    "spend_efficiency": ["type": "score", "score": 2, "confidence": 0.82],
                    "cheapness_priority": ["type": "noul", "noul": 0.42]
                ],
                "usage": ["input_tokens": 220, "output_tokens": 0, "cost": 0.000009]
            ])
        }
        do {
            let context = JevContextBuilder.build(accounts: [], localUsage: [:], artificialAnalysis: nil, prices: [:], task: "Refactor SwiftUI view")
            let result = try await JevClassifierClient(configuration: configuration()).classify(context: context, apiKey: "or-std-fixture")
            check(result.jevModel == "typesafe/jev-1.14" && result.tier == .balanced && result.recommendedCandidate != nil && result.inputTokens == 220,
                  "Jev Decisions API POST request and structured answer parsing")
        } catch {
            fputs("FAIL: Jev classifier transport: \(error.localizedDescription)\n", stderr); exit(1)
        }
        FixtureURLProtocol.handler = nil
        print("Passed \(checks) transport checks using isolated HTTP fixtures; no live credentials or network requests.")
    }
}
