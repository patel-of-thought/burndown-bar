import Foundation

enum AppIdentityTests {
    static func run() -> Int {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
            passed += 1
        }
        let bundle = Bundle.main
        check(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String == "BurndownBar", "bundle name")
        check(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "BurndownBar", "display name")
        check(bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "BurndownBar", "executable name")
        check(bundle.bundleURL.lastPathComponent == "BurndownBar.app", "app bundle path")
        check(bundle.executableURL?.lastPathComponent == "BurndownBar", "bundled executable path")
        check(bundle.bundleIdentifier == "local.burndownbar" && AppIdentity.bundleID == "local.burndownbar", "bundle identifier uses the BurndownBar name")

        check(SubscriptionCredentials.service == "local.burndownbar", "Keychain service uses the BurndownBar name")
        return passed
    }
}
