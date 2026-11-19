import Foundation

final class SubscriptionClient {
    private let session: URLSession
    var cachedCosts: (identity: String, value: UsageCosts)?
    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    func request(url: String, provider: String, headers: [String: String] = [:], body: JSON? = nil) async throws -> JSON {
        guard let result = try await requestValue(url: url, provider: provider, headers: headers, body: body) as? JSON else {
            throw SubscriptionError.message("The usage service sent an unexpected response.")
        }
        return result
    }
    func requestValue(url: String, provider: String, method: String? = nil, headers: [String: String] = [:], body: JSON? = nil) async throws -> Any {
        let result = try await requestStatus(url: url, provider: provider, method: method, headers: headers, body: body)
        if result.status == 401 || result.status == 403 { throw SubscriptionError.unauthorized(provider) }
        guard (200...299).contains(result.status) else { throw SubscriptionError.http(result.status) }
        return result.value
    }

    func requestStatus(url: String, provider: String, method: String? = nil, headers: [String: String] = [:], body: JSON? = nil) async throws -> (status: Int, value: Any) {
        let allowed = ["cursor.com", "api.factory.ai", "app.factory.ai", "status.factory.ai", "status.cursor.com",
                       "api.github.com", "app.warp.dev", "cloud.zed.dev", "opencode.ai", "openrouter.ai",
                       "cloudcode-pa.googleapis.com", "daily-cloudcode-pa.googleapis.com", "github.com",
                       "claude.ai", "cli-chat-proxy.grok.com", "grok.com", "chatgpt.com"]
        guard let url = URL(string: url), url.scheme == "https", allowed.contains(url.host ?? "") else {
            throw SubscriptionError.message("The usage endpoint is invalid.")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let method { request.httpMethod = method }
        if let body {
            if method == nil { request.httpMethod = "POST" }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SubscriptionError.message("The usage service sent an invalid response.") }
        let parsed = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? [:]
        return (http.statusCode, parsed)
    }

    func status(_ url: String) async -> (description: String, indicator: String)? {
        guard let json = try? await request(url: url, provider: "Status"), let status = json["status"] as? JSON,
              let description = string(status["description"]), let indicator = string(status["indicator"]) else { return nil }
        return (description, indicator)
    }

    static func placeholder(_ origin: AccountOrigin) -> Account {
        return Account(id: "direct-\(origin.rawValue)", name: origin.title,
            email: "\(origin.title) account", provider: origin.rawValue, authIndex: "",
            accountID: nil, disabled: false, plan: "Subscription", origin: origin,
            details: ProviderDetails(source: "Not connected", dashboardURL: URL(string: origin.dashboard)))
    }

    static func message(_ error: Error, provider: String) -> String {
        if let value = error as? SubscriptionError { return value.localizedDescription }
        if let value = error as? URLError {
            return value.code == .timedOut ? "\(provider)'s usage request timed out." : "Could not reach \(provider). Check your connection and refresh."
        }
        return "Could not read \(provider)'s usage response."
    }

    static func appVersion(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? JSON else { return nil }
        return string(plist["CFBundleShortVersionString"])
    }
}
