import Foundation

enum AccountOrigin: String, CaseIterable {
    case proxy, cursor, factory, codex, opencode, antigravity, copilot, warp, zed, grok, claude, openrouter
    static let additional: [AccountOrigin] = [.codex, .opencode, .antigravity, .copilot, .warp, .zed, .grok, .claude, .openrouter]
    /// Providers whose quota can be read either directly or through CLIProxyAPI's signed-in accounts.
    static let proxyCapable: [AccountOrigin] = [.codex, .grok, .claude]
    var supportsProxy: Bool { Self.proxyCapable.contains(self) }
    var isInferenceProvider: Bool { self == .openrouter }
    /// Maps CLIProxyAPI's credential type to the provider it serves.
    static func forProxyProvider(_ provider: String) -> AccountOrigin? {
        switch provider.lowercased() {
        case "codex", "openai": return .codex
        case "xai", "grok": return .grok
        case "claude", "anthropic": return .claude
        default: return nil
        }
    }
    var title: String {
        switch self {
        case .proxy: return "Proxy"
        case .cursor: return "Cursor"
        case .factory: return "Droid"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .antigravity: return "Antigravity"
        case .copilot: return "Copilot"
        case .warp: return "Warp"
        case .zed: return "Zed"
        case .grok: return "Grok"
        case .claude: return "Claude"
        case .openrouter: return "OpenRouter"
        }
    }
    var dashboard: String {
        switch self {
        case .opencode: return "https://opencode.ai/console"
        case .antigravity: return "https://antigravity.google/"
        case .copilot: return "https://github.com/settings/copilot"
        case .warp: return "https://app.warp.dev/"
        case .zed: return "https://zed.dev/account"
        case .grok: return "https://grok.com/"
        case .claude: return "https://claude.ai/settings/usage"
        case .openrouter: return "https://openrouter.ai/activity"
        case .cursor: return "https://cursor.com/dashboard?tab=usage"
        case .factory: return "https://app.factory.ai/settings/billing"
        case .codex: return "https://chatgpt.com/codex/settings/usage"
        case .proxy: return "http://127.0.0.1:8317"
        }
    }
}

struct ProviderDetails {
    var source: String
    var version: String?
    var status: String?
    var statusIndicator: String?
    var extraBalanceUSD: Double?
    var warning: String?
    var dashboardURL: URL?
}
