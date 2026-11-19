import AppKit

@MainActor final class ProviderSignIn {
    static let shared = ProviderSignIn()
    @discardableResult func open(_ origin: AccountOrigin) -> Bool {
        guard let url = URL(string: origin.dashboard), url.scheme == "https" else { return false }
        return NSWorkspace.shared.open(url)
    }
}
