import Foundation

/// `--live-check`: reads the proxy-backed providers and prints a summary without account emails or credential values. Nothing is saved.
enum LiveCheck {
    @MainActor static func run() async {
        let store = DashboardStore(persistPreferences: false)
        store.cursorEnabled = false; store.droidEnabled = false
        store.additionalEnabled = Dictionary(uniqueKeysWithValues: AccountOrigin.additional.map { ($0.rawValue, AccountOrigin.proxyCapable.contains($0)) })
        store.quotaSources = Dictionary(uniqueKeysWithValues: AccountOrigin.proxyCapable.map { ($0.rawValue, QuotaSource.proxy.rawValue) })
        store.accounts.removeAll()
        await store.refresh()
        if let error = store.connectionError { print("Proxy: \(error)") }
        for account in store.accounts {
            let low = account.minimum.map { "\(Int($0.rounded()))% lowest remaining" } ?? "no percentage"
            print("\(account.providerName) [\(account.origin.rawValue)] \(account.plan) · \(account.windows.count) windows · \(low) · \(account.error ?? "ok")")
        }
    }
}
