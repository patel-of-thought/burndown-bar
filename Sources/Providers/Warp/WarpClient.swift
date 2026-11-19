import Foundation

extension SubscriptionClient {
    func fetchWarp(key suppliedKey: String?, cookie suppliedCookie: String?) async throws -> (account: Account, source: String) {
        var account: Account
        var source = "Browser sign-in"
        var headers = ["x-warp-client-id": "warp-app", "x-warp-os-category": "macOS", "x-warp-os-name": "macOS",
                       "x-warp-os-version": ProcessInfo.processInfo.operatingSystemVersionString, "User-Agent": "Warp/1.0"]
        if let cookie = suppliedCookie ?? (suppliedKey == nil ? SubscriptionCredentials.cookie(.warp) : nil) { headers["Cookie"] = cookie }
        else if let key = suppliedKey ?? SubscriptionCredentials.providerKey(.warp) { headers["Authorization"] = "Bearer \(key)"; source = "Warp API key" }
        else { throw SubscriptionError.message("Sign into Warp or enter a Warp API key in Connections.") }
        let raw = try await request(url: "https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo", provider: "Warp", headers: headers, body: Self.warpQuery)
        account = try AdditionalParsers.warp(raw)
        return (account, source)
    }

    static let warpQuery: JSON = [
        "operationName": "GetRequestLimitInfo",
        "variables": ["requestContext": ["clientContext": [:], "osContext": ["category": "macOS", "name": "macOS", "version": "26.0"]]],
        "query": "query GetRequestLimitInfo($requestContext: RequestContext!) { user(requestContext: $requestContext) { __typename ... on UserOutput { user { requestLimitInfo { isUnlimited nextRefreshTime requestLimit requestsUsedSinceLastRefresh } bonusGrants { requestCreditsGranted requestCreditsRemaining expiration } workspaces { bonusGrantsInfo { grants { requestCreditsGranted requestCreditsRemaining expiration } } } } } } }"
    ]
}
