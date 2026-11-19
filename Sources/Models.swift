import Foundation
import CoreFoundation

typealias JSON = [String: Any]

func number(_ value: Any?) -> Double? {
    if let n = value as? NSNumber {
        guard CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue.isFinite ? n.doubleValue : nil
    }
    if let s = value as? String, let n = Double(s), n.isFinite { return n }
    return nil
}

func string(_ value: Any?) -> String? {
    if let s = value as? String, !s.isEmpty { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return nil
}

func date(_ value: Any?) -> Date? {
    if let n = number(value), n > 0 { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
    guard let s = value as? String else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}

func duration(_ seconds: TimeInterval) -> String {
    guard seconds > 0 else { return "now" }
    let minutes = max(1, Int(ceil(seconds / 60)))
    if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
    if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
    return "\(minutes)m"
}

func compactCount(_ value: Int64) -> String {
    let n = Double(value)
    return n >= 1e9 ? String(format: "%.1fB", n / 1e9)
        : n >= 1e6 ? String(format: "%.1fM", n / 1e6)
        : n >= 1e3 ? String(format: "%.1fK", n / 1e3) : String(value)
}

struct Account: Identifiable {
    let id: String
    let name: String
    let email: String
    let provider: String
    let authIndex: String
    let accountID: String?
    let disabled: Bool
    var plan: String
    var windows: [QuotaWindow] = []
    var credits: String?
    var error: String?
    var updatedAt: Date?
    var origin: AccountOrigin = .proxy
    var details: ProviderDetails?
    var costs: UsageCosts?
    var providerUserID: String?
    var facts: [UsageFact] = []
    var openRouter: OpenRouterSnapshot?

    var providerName: String { Self.providerName(for: provider) }
    /// The provider this CLIProxyAPI credential serves, when it is one the bar can read through the proxy.
    var proxyOrigin: AccountOrigin? { origin == .proxy ? AccountOrigin.forProxyProvider(provider) : nil }
    static func providerName(for provider: String) -> String {
        switch provider {
        case "codex", "openai": return "Codex"
        case "claude", "anthropic": return "Claude"
        case "github-copilot", "copilot": return "Copilot"
        case "antigravity": return "Antigravity"
        case "gemini": return "Gemini"
        case "cursor": return "Cursor"
        case "factory", "droid": return "Droid"
        case "xai", "grok": return "Grok"
        case "opencode", "opencode-go", "opencodego": return "OpenCode"
        case "warp": return "Warp"
        case "zed": return "Zed"
        case "openrouter": return "OpenRouter"
        default: return provider.capitalized
        }
    }
    var keyWindows: [QuotaWindow] { Array(windows.filter { !$0.id.contains("review") }.prefix(origin == .proxy && providerName == "Codex" ? 4 : 6)) }
    var minimum: Double? { keyWindows.compactMap(\.remaining).min() }
    var isStale: Bool { error != nil || updatedAt.map { Date().timeIntervalSince($0) > 600 } == true }

    static func parse(_ raw: JSON) -> Account? {
        let metadata = raw["metadata"] as? JSON ?? [:]
        let attributes = raw["attributes"] as? JSON ?? [:]
        let name = string(raw["name"]) ?? string(raw["id"]) ?? "Account"
        guard let index = string(raw["auth_index"] ?? raw["authIndex"]), !index.isEmpty else { return nil }
        let provider = (string(raw["provider"]) ?? string(raw["type"]) ?? "unknown").lowercased()
        let email = string(raw["email"]) ?? string(metadata["email"]) ?? string(attributes["email"]) ?? name
        var accountID = string(raw["chatgpt_account_id"] ?? metadata["chatgpt_account_id"] ?? attributes["chatgpt_account_id"])
        // Management responses may expose a decoded identity object, never an access token.
        for candidate in [raw["id_token"], metadata["id_token"], attributes["id_token"]] {
            if let identity = candidate as? JSON {
                let auth = identity["https://api.openai.com/auth"] as? JSON ?? identity
                accountID = accountID ?? string(auth["chatgpt_account_id"])
            }
        }
        var account = Account(id: index, name: name, email: email, provider: provider, authIndex: index,
                       accountID: accountID, disabled: raw["disabled"] as? Bool ?? false,
                       plan: string(raw["plan_type"] ?? metadata["plan_type"])?.capitalized ?? "Subscription")
        account.providerUserID = string(raw["sub"] ?? raw["user_id"] ?? raw["userId"]
            ?? metadata["sub"] ?? metadata["user_id"] ?? attributes["sub"] ?? attributes["user_id"])
        return account
    }
}
