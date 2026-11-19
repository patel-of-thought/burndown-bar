import Foundation

extension SubscriptionClient {
    struct GitHubDeviceCode {
        let deviceCode: String
        let userCode: String
        let interval: Int
        let expires: Int
    }
    func githubDeviceCode() async throws -> GitHubDeviceCode {
        let raw = try await request(url: "https://github.com/login/device/code", provider: "GitHub", body: ["client_id": "Iv1.b507a08c87ecfe98", "scope": "read:user"])
        guard let device = string(raw["device_code"]), let user = string(raw["user_code"]),
              let expires = number(raw["expires_in"]), expires > 0, expires <= 3600 else { throw SubscriptionError.message("GitHub did not return a valid sign-in code.") }
        return GitHubDeviceCode(deviceCode: device, userCode: user, interval: max(5, min(60, Int(number(raw["interval"]) ?? 5))), expires: Int(expires))
    }
    func githubPoll(_ code: GitHubDeviceCode) async throws -> String {
        let deadline = Date().addingTimeInterval(Double(code.expires))
        var interval = code.interval
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            try Task.checkCancellation()
            guard Date() < deadline else { break }
            let raw = try await request(url: "https://github.com/login/oauth/access_token", provider: "GitHub", body: [
                "client_id": "Iv1.b507a08c87ecfe98", "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            try Task.checkCancellation()
            guard Date() < deadline else { break }
            if let token = string(raw["access_token"]) { return token }
            switch string(raw["error"]) {
            case "authorization_pending": continue
            case "slow_down": interval = min(120, interval + 5)
            case "access_denied": throw SubscriptionError.message("GitHub sign-in was declined.")
            case "expired_token": throw SubscriptionError.message("GitHub sign-in expired. Start again for a new code.")
            default: throw SubscriptionError.message("GitHub sign-in could not be completed.")
            }
        }
        throw SubscriptionError.message("GitHub sign-in expired. Start again for a new code.")
    }
}
