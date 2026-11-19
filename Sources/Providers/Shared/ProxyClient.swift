import Foundation

final class ProxyClient {
    let config: ProxyConfiguration
    private let session: URLSession
    private var version = "v8"
    init(config: ProxyConfiguration, configuration: URLSessionConfiguration = .ephemeral) {
        self.config = config
        let settings = configuration
        settings.timeoutIntervalForRequest = 25
        settings.timeoutIntervalForResource = 40
        settings.httpShouldSetCookies = false
        settings.urlCache = nil
        settings.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: settings, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    private func request(_ path: String, method: String = "GET", body: JSON? = nil) async throws -> JSON {
        let url = URL(string: "http://\(config.endpoint)/\(version)/management\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(config.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProxyError.message("The proxy sent an invalid response.") }
        guard (200...299).contains(response.statusCode) else { throw ProxyError.http(response.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? JSON else {
            throw ProxyError.message("The proxy sent an unexpected response.")
        }
        return json
    }

    func accounts() async throws -> [Account] {
        let response: JSON
        do { response = try await request("/credentials") }
        catch ProxyError.http(404) {
            version = "v0"
            response = try await request("/auth-files")
        }
        guard let files = response["files"] as? [JSON] else { throw ProxyError.message("The proxy's account list was not recognized.") }
        return files.compactMap(Account.parse).sorted { $0.email.localizedStandardCompare($1.email) == .orderedAscending }
    }

    /// Sends one provider request through the proxy using the signed-in account's own token.
    private func call(_ account: Account, method: String = "GET", url: String, headers: [String: String], data: String? = nil) async throws -> JSON {
        var payload: JSON = ["authIndex": account.authIndex, "method": method, "url": url, "header": headers]
        if let data { payload["data"] = data }
        let envelope = try await request(version == "v8" ? "/requests/api-call" : "/api-call", method: "POST", body: payload)
        let status = Int(number(envelope["status_code"]) ?? 0)
        guard (200...299).contains(status) else {
            if status == 401 || status == 403 { throw ProxyError.message("Session expired. Reconnect this account in CLIProxyAPI.") }
            throw ProxyError.http(status)
        }
        if let value = envelope["body"] as? JSON { return value }
        if let value = envelope["body"] as? String, let data = value.data(using: .utf8),
           let value = try JSONSerialization.jsonObject(with: data) as? JSON { return value }
        throw ProxyError.message("The provider sent an unexpected quota response.")
    }

    func quota(for account: Account) async throws -> Account {
        var result = account
        guard let origin = account.proxyOrigin else {
            throw ProxyError.message("CLIProxyAPI does not provide quota for this account type. Connect it in Connections.")
        }
        if account.disabled { result.error = "Disabled in CLIProxyAPI"; return result }
        switch origin {
        case .codex:
            var headers = ["Authorization": "Bearer $TOKEN$", "Content-Type": "application/json", "User-Agent": SubscriptionClient.codexUserAgent]
            if let id = account.accountID { headers["Chatgpt-Account-Id"] = id }
            QuotaParser.applyCodex(try await call(account, url: "https://chatgpt.com/backend-api/wham/usage", headers: headers), to: &result)
            guard !result.windows.isEmpty else { throw ProxyError.message("No quota windows were returned for this account.") }
        case .grok:
            let headers = ["Authorization": "Bearer $TOKEN$", "x-xai-token-auth": "xai-grok-cli", "x-grok-client-version": "1.0.70",
                           "User-Agent": "grok-pager/1.0.70 grok-shell/1.0.70 (macos; aarch64)"]
            let parsed = try AdditionalParsers.grok(try await call(account, url: "https://cli-chat-proxy.grok.com/v1/billing?format=credits", headers: headers))
            result.windows = parsed.windows; result.plan = parsed.plan
            if let balance = parsed.details?.extraBalanceUSD {
                result.facts = [UsageFact(label: "Prepaid balance", value: balance.formatted(.currency(code: "USD")))]
            }
        case .claude:
            let headers = ["Authorization": "Bearer $TOKEN$", "Content-Type": "application/json", "anthropic-beta": "oauth-2025-04-20",
                           "User-Agent": "claude-cli/2.1.280 (external, cli)"]
            result.windows = QuotaParser.claude(try await call(account, url: "https://api.anthropic.com/api/oauth/usage", headers: headers))
            guard !result.windows.isEmpty else { throw ProxyError.message("Claude did not return subscription usage windows.") }
        default:
            throw ProxyError.message("CLIProxyAPI does not provide quota for this account type. Connect it in Connections.")
        }
        result.error = nil
        result.updatedAt = Date()
        return result
    }

}
