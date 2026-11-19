import Foundation

/// Identity used for this app's preferences and running instance.
enum AppIdentity {
    static let bundleID = "local.burndownbar"
    static let allBundleIDs = [bundleID]
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown" }
}
