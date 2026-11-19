import AppKit
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case subscriptions, inference, rankings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .subscriptions: return "Subscriptions"
        case .inference: return "Inference"
        case .rankings: return "Rankings"
        }
    }
}

@MainActor final class DashboardStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var refreshing = false
    /// Daily token history read from CLIProxyAPI's own databases, keyed by provider name.
    @Published var localUsage: [String: [UsageSeries]] = [:]
    @Published var connectionError: String?
    @Published var endpoint = "127.0.0.1:8317"
    @Published var lastRefresh: Date?
    @Published var now = Date()
    @Published var tab = "Overview"
    @Published private(set) var section: DashboardSection = .subscriptions
    @Published var artificialAnalysis: ArtificialAnalysisSnapshot?
    @Published var artificialAnalysisError: String?
    @Published var artificialAnalysisLoading = false
    @Published var artificialAnalysisKeyInput = ""
    @Published var selectedID = ""
    @Published var settingsVisible = false
    @Published var connectionVisible = false
    @Published private(set) var connectionReturnsToPreferences = false
    @Published var cursorEnabled: Bool { didSet { if persistPreferences { UserDefaults.standard.set(cursorEnabled, forKey: "cursorEnabled") } } }
    @Published var droidEnabled: Bool { didSet { if persistPreferences { UserDefaults.standard.set(droidEnabled, forKey: "droidEnabled") } } }
    @Published var cursorSource: String { didSet { if persistPreferences { UserDefaults.standard.set(cursorSource, forKey: "cursorSource") } } }
    @Published var additionalEnabled: [String: Bool] { didSet { if persistPreferences { UserDefaults.standard.set(additionalEnabled, forKey: "additionalEnabled") } } }
    @Published var quotaSources: [String: String] { didSet { if persistPreferences { UserDefaults.standard.set(quotaSources, forKey: "quotaSources") } } }
    @Published var connectionProvider = AccountOrigin.opencode
    @Published var connectionCredential = ""
    @Published var openRouterStandardKey = ""
    @Published var connectionUsesCookie = false
    @Published var workspaceID: String { didSet { if persistPreferences { UserDefaults.standard.set(workspaceID, forKey: "opencodeWorkspace") } } }
    @Published var signInMessage: String?
    @Published var githubCode: String?
    @Published var signingIn = false
    private var loginTask: Task<Void, Never>?
    @Published var privacy: Bool { didSet { if persistPreferences { UserDefaults.standard.set(privacy, forKey: "privacy") } } }
    @Published var developerMode: Bool { didSet {
        if persistPreferences {
            UserDefaults.standard.set(developerMode, forKey: "developerMode")
            UserDefaults.standard.synchronize()
        }
    } }
    @Published var interval: Int { didSet { if persistPreferences { UserDefaults.standard.set(interval, forKey: "refreshInterval") } } }
    var statusChanged: (() -> Void)?
    private var timer: Timer?
    private var lastAttempt: Date?
    private var refreshQueued = false
    private let subscriptions = SubscriptionClient()
    private let artificialAnalysisClient = ArtificialAnalysisClient()
    private let persistPreferences: Bool

    init(persistPreferences: Bool = true) {
        self.persistPreferences = persistPreferences
        let savedCursorSource = UserDefaults.standard.string(forKey: "cursorSource") ?? "browser"
        cursorSource = ["browser", "manual", "desktop"].contains(savedCursorSource) ? savedCursorSource : "browser"
        additionalEnabled = UserDefaults.standard.dictionary(forKey: "additionalEnabled") as? [String: Bool] ?? [:]
        let savedQuotaSources = UserDefaults.standard.dictionary(forKey: "quotaSources") as? [String: String] ?? [:]
        quotaSources = savedQuotaSources
        workspaceID = UserDefaults.standard.string(forKey: "opencodeWorkspace") ?? ""
        privacy = UserDefaults.standard.bool(forKey: "privacy")
        developerMode = UserDefaults.standard.bool(forKey: "developerMode")
        section = UserDefaults.standard.string(forKey: "dashboardSection").flatMap(DashboardSection.init(rawValue:)) ?? .subscriptions
        let saved = UserDefaults.standard.integer(forKey: "refreshInterval")
        interval = [60, 120, 300, 600].contains(saved) ? saved : 120
        cursorEnabled = UserDefaults.standard.object(forKey: "cursorEnabled") as? Bool ?? true
        droidEnabled = UserDefaults.standard.object(forKey: "droidEnabled") as? Bool ?? true
        if cursorEnabled { accounts.append(SubscriptionClient.placeholder(.cursor)) }
        if droidEnabled { accounts.append(SubscriptionClient.placeholder(.factory)) }
        for origin in AccountOrigin.additional where usesDirect(origin) { accounts.append(SubscriptionClient.placeholder(origin)) }
    }
    var sectionAccounts: [Account] {
        accounts.filter { account in
            switch section {
            case .subscriptions: return !(account.proxyOrigin ?? account.origin).isInferenceProvider
            case .inference: return (account.proxyOrigin ?? account.origin).isInferenceProvider
            case .rankings: return false
            }
        }
    }
    var providers: [String] { Array(Set(sectionAccounts.map(\.providerName))).sorted() }
    var filtered: [Account] { tab == "Overview" ? sectionAccounts : sectionAccounts.filter { $0.providerName == tab } }
    var selected: Account? { filtered.first { $0.id == selectedID } ?? filtered.first }
    func selectSection(_ next: DashboardSection) {
        guard section != next else { return }
        section = next
        tab = "Overview"
        selectedID = ""
        if persistPreferences { UserDefaults.standard.set(next.rawValue, forKey: "dashboardSection") }
        if next == .rankings { Task { await refreshArtificialAnalysis() } }
    }
    var hasArtificialAnalysisKey: Bool {
        SubscriptionCredentials.namedKey(account: "artificial-analysis-key", variable: "ARTIFICIAL_ANALYSIS_API_KEY") != nil
    }
    func saveArtificialAnalysisKey() {
        do {
            try SubscriptionCredentials.save(artificialAnalysisKeyInput, account: "artificial-analysis-key")
            artificialAnalysisKeyInput = ""
            artificialAnalysis = nil
            artificialAnalysisError = nil
            Task { await refreshArtificialAnalysis(force: true) }
        } catch { artificialAnalysisError = error.localizedDescription }
    }
    func refreshArtificialAnalysis(force: Bool = false) async {
        guard !artificialAnalysisLoading else { return }
        guard let key = SubscriptionCredentials.namedKey(account: "artificial-analysis-key", variable: "ARTIFICIAL_ANALYSIS_API_KEY") else { return }
        if !force, let snapshot = artificialAnalysis, Date().timeIntervalSince(snapshot.fetchedAt) < 6 * 3600 { return }
        artificialAnalysisLoading = true
        defer { artificialAnalysisLoading = false }
        do {
            artificialAnalysis = try await artificialAnalysisClient.rankings(key: key)
            artificialAnalysisError = nil
        } catch { artificialAnalysisError = error.localizedDescription }
    }
    var healthyCount: Int { accounts.filter { !isStale($0) && $0.updatedAt != nil && !$0.disabled }.count }
    var statusPercent: String? {
        return accounts.filter { !isStale($0) && !$0.disabled }.compactMap(\.minimum).min().map { "\(Int($0.rounded()))%" }
    }
    func isStale(_ account: Account) -> Bool { account.isStale || (account.origin == .proxy && connectionError != nil) }
    func isProviderConnected(_ origin: AccountOrigin) -> Bool {
        accounts.contains { account in
            (account.proxyOrigin ?? account.origin) == origin && shouldShow(account)
                && !account.disabled && account.updatedAt != nil && !isStale(account)
        }
    }
    func openConnectionSettings(_ origin: AccountOrigin) {
        connectionReturnsToPreferences = settingsVisible
        if connectionProvider != origin {
            cancelSignIn()
            connectionCredential = ""
            openRouterStandardKey = ""
            signInMessage = nil
        }
        connectionProvider = origin
        connectionUsesCookie = [.cursor, .zed, .opencode, .claude].contains(origin)
        settingsVisible = false
        connectionVisible = true
    }
    func closeConnectionSettings() {
        connectionVisible = false
        settingsVisible = connectionReturnsToPreferences
    }
    var sharedQuotaSource: QuotaSource {
        quotaSources["default"].flatMap(QuotaSource.init(rawValue:)) ?? .proxy
    }
    func quotaSource(for origin: AccountOrigin) -> QuotaSource {
        guard origin.supportsProxy && sharedQuotaSource == .proxy else { return .direct }
        return quotaSources[origin.rawValue].flatMap(QuotaSource.init(rawValue:)) ?? .proxy
    }
    func setQuotaSource(_ source: QuotaSource) {
        guard sharedQuotaSource != source else { return }
        quotaSources["default"] = source.rawValue
        providersChanged()
    }
    func setQuotaSource(_ source: QuotaSource, for origin: AccountOrigin) {
        guard origin.supportsProxy && sharedQuotaSource == .proxy && quotaSource(for: origin) != source else { return }
        if source == .proxy { quotaSources.removeValue(forKey: origin.rawValue) }
        else { quotaSources[origin.rawValue] = source.rawValue }
        providersChanged()
    }
    func usesProxy(_ origin: AccountOrigin) -> Bool { origin.supportsProxy && isEnabled(origin) && quotaSource(for: origin) == .proxy }
    func usesDirect(_ origin: AccountOrigin) -> Bool { isEnabled(origin) && !(origin.supportsProxy && quotaSource(for: origin) == .proxy) }
    private func shouldShow(_ account: Account) -> Bool {
        account.origin == .proxy ? account.proxyOrigin.map(usesProxy) ?? false : usesDirect(account.origin)
    }
    func displayEmail(_ account: Account) -> String {
        guard privacy else { return account.email }
        if let at = account.email.firstIndex(of: "@") { return String(account.email.prefix(1)) + "•••" + account.email[at...] }
        return "Account \((accounts.firstIndex { $0.id == account.id } ?? 0) + 1)"
    }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                if self.lastAttempt.map({ Date().timeIntervalSince($0) >= Double(self.interval) }) ?? true {
                    await self.refresh()
                }
            }
        }
        Task { await refresh() }
    }
    func refresh() async {
        guard !refreshing else { refreshQueued = true; return }
        refreshing = true
        lastAttempt = Date()
        defer {
            refreshing = false; now = Date(); statusChanged?()
            if refreshQueued { refreshQueued = false; Task { await refresh() } }
        }
        accounts.removeAll { !shouldShow($0) }
        async let cursorRead: Void = refreshDirect(.cursor, enabled: cursorEnabled)
        async let factoryRead: Void = refreshDirect(.factory, enabled: droidEnabled)
        async let remainingRead: Void = refreshAdditional()
        await refreshProxy()
        _ = await (cursorRead, factoryRead, remainingRead)
        if section == .rankings { await refreshArtificialAnalysis() }
        if persistPreferences { localUsage = await Task.detached(priority: .utility) { ProxyUsageReader.load() }.value }
        lastRefresh = Date()
        if !providers.contains(tab) && tab != "Overview" { tab = "Overview" }
    }
    private func proxyPlaceholder(_ origin: AccountOrigin, error: String) -> Account {
        var account = Account(id: "missing-\(origin.rawValue)", name: origin.title, email: "\(origin.title) account",
                              provider: origin.rawValue, authIndex: "", accountID: nil, disabled: false, plan: "Subscription")
        account.error = error
        return account
    }
    private func refreshProxy() async {
        let origins = AccountOrigin.proxyCapable.filter { usesProxy($0) }
        guard !origins.isEmpty else { accounts.removeAll { $0.origin == .proxy }; connectionError = nil; return }
        do {
            let configuration = try ProxyConfiguration.load()
            endpoint = configuration.endpoint
            let client = ProxyClient(config: configuration)
            let listed = try await client.accounts().filter { $0.proxyOrigin.map(origins.contains) ?? false }
            let previous = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let proxyAccounts = listed.map { account in
                var item = account
                if let prior = previous[item.id] {
                    item.windows = prior.windows; item.credits = prior.credits
                    item.updatedAt = prior.updatedAt; item.plan = prior.plan; item.error = prior.error
                    item.details = prior.details; item.costs = prior.costs; item.facts = prior.facts
                }
                return item
            }.sorted { ($0.providerName, $0.email.lowercased()) < ($1.providerName, $1.email.lowercased()) }
            let missing = origins.filter { origin in !listed.contains { $0.proxyOrigin == origin } }.map {
                proxyPlaceholder($0, error: "No \($0.title) account is signed in to CLIProxyAPI. Add one there, or choose Direct in Preferences → Quota source.")
            }
            accounts = proxyAccounts + missing + accounts.filter { $0.origin != .proxy }
            connectionError = nil
            // Query sequentially to avoid bursts against the provider's quota endpoint.
            for account in listed {
                do {
                    let fresh = try await client.quota(for: account)
                    if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = fresh }
                } catch {
                    if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                        accounts[index].error = Self.message(for: error)
                    }
                }
                statusChanged?()
            }
        } catch {
            connectionError = Self.message(for: error)
            for origin in origins where !accounts.contains(where: { $0.proxyOrigin == origin }) {
                accounts.insert(proxyPlaceholder(origin, error: connectionError ?? ""), at: 0)
            }
        }
    }
    private func refreshDirect(_ origin: AccountOrigin, enabled: Bool) async {
        guard enabled else { return }
        if !accounts.contains(where: { $0.origin == origin }) { accounts.append(SubscriptionClient.placeholder(origin)) }
        do {
            let fresh: Account
            if origin == .cursor {
                fresh = try await subscriptions.cursor { [weak self] account in
                    await MainActor.run {
                        guard let self, let index = self.accounts.firstIndex(where: { $0.origin == .cursor }) else { return }
                        var account = account
                        account.costs = self.accounts[index].costs
                        self.accounts[index] = account
                        self.statusChanged?()
                    }
                }
            } else { fresh = try await subscriptions.factory() }
            if isEnabled(origin), let index = accounts.firstIndex(where: { $0.origin == origin }) { accounts[index] = fresh }
        } catch {
            if let index = accounts.firstIndex(where: { $0.origin == origin }) {
                accounts[index].error = SubscriptionClient.message(error, provider: origin == .cursor ? "Cursor" : "Droid")
            }
        }
        statusChanged?()
    }
    func isEnabled(_ origin: AccountOrigin) -> Bool {
        if origin == .cursor { return cursorEnabled }
        if origin == .factory { return droidEnabled }
        return additionalEnabled[origin.rawValue] ?? true
    }
    func setEnabled(_ origin: AccountOrigin, _ enabled: Bool) {
        if origin == .cursor { cursorEnabled = enabled }
        else if origin == .factory { droidEnabled = enabled }
        else { additionalEnabled[origin.rawValue] = enabled }
        providersChanged()
    }
    private func refreshAdditional() async {
        let origins = AccountOrigin.additional.filter { usesDirect($0) }
        for origin in origins where !accounts.contains(where: { $0.origin == origin }) { accounts.append(SubscriptionClient.placeholder(origin)) }
        await withTaskGroup(of: (AccountOrigin, Result<Account, Error>).self) { group in
            for origin in origins {
                group.addTask { [subscriptions] in
                    do { return (origin, .success(try await subscriptions.additional(origin))) }
                    catch { return (origin, .failure(error)) }
                }
            }
            for await (origin, result) in group {
                guard usesDirect(origin), let index = accounts.firstIndex(where: { $0.origin == origin }) else { continue }
                switch result {
                case .success(let account): accounts[index] = account
                case .failure(let error): accounts[index].error = SubscriptionClient.message(error, provider: origin.title)
                }
                statusChanged?()
            }
        }
    }
    func connect(_ origin: AccountOrigin) {
        guard !signingIn else { return }
        signInMessage = nil
        if origin.supportsProxy && quotaSource(for: origin) == .proxy { openProxy(); return }
        if origin == .codex {
            signInMessage = "Run codex login in a terminal, then refresh here, or paste an access token below."
            Task { await refresh() }
            return
        }
        if origin == .copilot { signInCopilot(); return }
        if origin == .antigravity {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Antigravity.app"), configuration: .init()) { _, _ in }
            signInMessage = "Sign into Antigravity, then refresh here. Usage is read from its local service."
            return
        }
        if origin == .grok {
            signInMessage = "Sign in using the Grok CLI, then enter its access token below. Grok's billing endpoint no longer accepts cookies alone."
            NSWorkspace.shared.open(URL(string: origin.dashboard)!)
            return
        }
        if origin == .openrouter {
            signInMessage = "Create a Management Key on OpenRouter (recommended for 30-day tokens, cache analytics & key caps), or paste a standard API key below."
            NSWorkspace.shared.open(URL(string: "https://openrouter.ai/settings/management-keys")!)
            return
        }
        if origin == .cursor && cursorSource == "desktop" {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Cursor.app"), configuration: .init()) { _, _ in }
            signInMessage = "Sign into Cursor.app, then refresh here."
            return
        }
        if origin == .cursor && cursorSource == "browser" { signInCursorBrowser(); return }
        guard ProviderSignIn.shared.open(origin) else {
            signInMessage = "Could not open your default browser. Open \(origin.dashboard) directly to sign in."
            return
        }
        connectionUsesCookie = true
        signInMessage = "Opened \(origin.title) in your default browser with your usual profile. After signing in, return here, paste its Cookie header below and choose Save & connect. Opening the browser does not import its session automatically."
    }
    private func signInCursorBrowser() {
        signingIn = true
        signInMessage = "Reading Cursor sign-in from your default browser…"
        loginTask = Task {
            defer { signingIn = false; loginTask = nil }
            do {
                // Only this explicit Connect action may display a browser Keychain prompt.
                do { _ = try await BrowserCursorSession.session(allowInteraction: true) }
                catch BrowserCursorSession.ReadError.signedOut {
                    guard ProviderSignIn.shared.open(.cursor) else {
                        throw BrowserCursorSession.ReadError.unavailable("Could not open your default browser. Open cursor.com to sign in, then refresh.")
                    }
                    signInMessage = "Sign into Cursor in your default browser. Waiting for its session automatically…"
                    let deadline = Date().addingTimeInterval(180)
                    while true {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        try Task.checkCancellation()
                        guard Date() < deadline else {
                            throw BrowserCursorSession.ReadError.unavailable("Still waiting for Cursor sign-in. After signing in, choose Connect from default browser again.")
                        }
                        do { _ = try await BrowserCursorSession.session(allowInteraction: true); break }
                        catch BrowserCursorSession.ReadError.signedOut { continue }
                    }
                }
                try Task.checkCancellation()
                signInMessage = "Cursor session imported from your default browser. Checking usage…"
                setEnabled(.cursor, true)
            } catch is CancellationError { signInMessage = "Sign-in cancelled." }
            catch { signInMessage = error.localizedDescription }
        }
    }
    private func signInCopilot() {
        guard !signingIn else { return }
        signingIn = true; githubCode = nil
        loginTask = Task {
            defer { signingIn = false; githubCode = nil; loginTask = nil }
            do {
                let code = try await subscriptions.githubDeviceCode()
                githubCode = code.userCode
                signInMessage = "Enter this code on GitHub to authorize your own Copilot connection."
                NSWorkspace.shared.open(URL(string: "https://github.com/login/device")!)
                let token = try await subscriptions.githubPoll(code)
                try Task.checkCancellation()
                try SubscriptionCredentials.save(token, account: "copilot-key")
                UserDefaults.standard.set("key", forKey: "authMode-copilot")
                signInMessage = "Copilot signed in. Checking usage…"
                setEnabled(.copilot, true)
            } catch is CancellationError { signInMessage = "Sign-in cancelled." }
            catch { signInMessage = error.localizedDescription }
        }
    }
    func cancelSignIn() { loginTask?.cancel() }
    func saveConnectionCredential() {
        do {
            let origin = connectionProvider
            if origin == .openrouter {
                let mgmt = connectionCredential.trimmingCharacters(in: .whitespacesAndNewlines)
                let std = openRouterStandardKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !mgmt.isEmpty || !std.isEmpty else {
                    throw SubscriptionError.message("Enter a Management Key and/or Standard API Key before saving.")
                }
                if !mgmt.isEmpty { try SubscriptionCredentials.save(mgmt, account: "openrouter-key") }
                if !std.isEmpty { try SubscriptionCredentials.save(std, account: "openrouter-standard-key") }
                UserDefaults.standard.set("key", forKey: "authMode-openrouter")
                connectionCredential = ""
                openRouterStandardKey = ""
                signInMessage = "Saved in BurndownBar's Keychain. Checking usage…"
                setEnabled(.openrouter, true)
                return
            }
            let useCookie = [.cursor, .claude].contains(origin) || connectionUsesCookie
            var value = connectionCredential.trimmingCharacters(in: .whitespacesAndNewlines)
            if useCookie && value.lowercased().hasPrefix("cookie:") { value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            try SubscriptionCredentials.save(value, account: "\(origin.rawValue)-\(useCookie ? "cookie" : "key")")
            UserDefaults.standard.set(useCookie ? "cookie" : "key", forKey: "authMode-\(origin.rawValue)")
            if origin == .cursor { cursorSource = "manual" }
            connectionCredential = ""
            signInMessage = "Saved in BurndownBar's Keychain. Checking usage…"
            setEnabled(origin, true)
        } catch { signInMessage = error.localizedDescription }
    }
    var openRouterHasManagementKey: Bool {
        SubscriptionCredentials.namedKey(account: "openrouter-key", variable: "OPENROUTER_MANAGEMENT_KEY") != nil
    }
    var openRouterHasStandardKey: Bool {
        SubscriptionCredentials.namedKey(account: "openrouter-standard-key", variable: "OPENROUTER_API_KEY") != nil
    }
    func openDashboard(_ account: Account) {
        if let url = account.details?.dashboardURL { NSWorkspace.shared.open(url) }
    }
    func providersChanged() {
        accounts.removeAll { !shouldShow($0) }
        if cursorEnabled && !accounts.contains(where: { $0.origin == .cursor }) { accounts.append(SubscriptionClient.placeholder(.cursor)) }
        if droidEnabled && !accounts.contains(where: { $0.origin == .factory }) { accounts.append(SubscriptionClient.placeholder(.factory)) }
        for origin in AccountOrigin.additional where usesDirect(origin) && !accounts.contains(where: { $0.origin == origin }) {
            accounts.append(SubscriptionClient.placeholder(origin))
        }
        if tab != "Overview" && !providers.contains(tab) { tab = "Overview" }
        Task { await refresh() }
    }
    static func message(for error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost:
                return "Proxy offline. Open CLIProxyAPI and start the proxy."
            case .timedOut: return "The request timed out. Try refreshing again."
            default: return "Could not reach the local proxy. Check that CLIProxyAPI is running."
            }
        }
        if let error = error as? ProxyError { return error.localizedDescription }
        return "Could not read quota data. Try refreshing or reconnect the account in CLIProxyAPI."
    }
    func select(_ account: Account) {
        let target: DashboardSection = (account.proxyOrigin ?? account.origin).isInferenceProvider ? .inference : .subscriptions
        selectSection(target)
        selectedID = account.id
        tab = account.providerName
    }
    func setOpenRouterKeyDisabled(hash: String, disabled: Bool) async throws {
        try await subscriptions.updateOpenRouterKey(hash: hash, disabled: disabled)
        await refresh()
    }
    func setOpenRouterKeyLimit(hash: String, limitUSD: Double?, reset: String?) async throws {
        try await subscriptions.updateOpenRouterKey(hash: hash, limitUSD: limitUSD, clearLimit: limitUSD == nil, limitReset: reset)
        await refresh()
    }
    func setOpenRouterZDR(enabled: Bool, guardrailID: String?, keyHashes: [String]) async throws {
        try await subscriptions.setOpenRouterZDR(enabled: enabled, guardrailID: guardrailID, keyHashes: keyHashes)
        await refresh()
    }
    func openProxy() {
        let url = URL(fileURLWithPath: "/Applications/EasyCLIProxyAPI.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
    }
}
