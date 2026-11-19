import Foundation

extension SubscriptionClient {
    func factory(credentials supplied: SubscriptionCredentials.FactorySession? = nil, detectVersion: Bool = true) async throws -> Account {
        var headers = ["Origin": "https://app.factory.ai", "Referer": "https://app.factory.ai/", "x-factory-client": "web-app"]
        let source: String
        if supplied == nil, let cookie = SubscriptionCredentials.cookie(.factory) { headers["Cookie"] = cookie; source = "Factory browser sign-in" }
        else {
            let credentials = try supplied ?? SubscriptionCredentials.factory()
            headers["Authorization"] = "Bearer \(credentials.token)"; source = credentials.source
        }
        let requestHeaders = headers
        async let health = status("https://status.factory.ai/api/v2/status.json")
        async let authRead = factoryAuth(headers: requestHeaders)
        let limits = try await request(url: "https://api.factory.ai/api/billing/limits", provider: "Droid", headers: requestHeaders)
        let (auth, service) = await (authRead, health)
        let profile = auth?["userProfile"] as? JSON ?? [:]
        var account = Account(id: "direct-factory", name: "Droid", email: string(profile["email"]) ?? "Factory account",
            provider: "factory", authIndex: "", accountID: string(profile["id"]), disabled: false,
            plan: SubscriptionParser.factoryPlan(auth ?? [:], limits: limits), origin: .factory)
        account.windows = try SubscriptionParser.factory(limits: limits)
        account.updatedAt = Date()
        account.details = ProviderDetails(source: source, version: detectVersion ? await Self.droidVersion() : nil,
            status: service?.description, statusIndicator: service?.indicator,
            extraBalanceUSD: number(limits["extraUsageBalanceCents"]).map { $0 / 100 },
            warning: auth == nil ? "Plan details are currently unavailable." : nil,
            dashboardURL: URL(string: "https://app.factory.ai/settings/billing"))
        return account
    }

    private func factoryAuth(headers: [String: String]) async -> JSON? {
        for base in ["https://api.factory.ai", "https://app.factory.ai"] {
            if let auth = try? await request(url: base + "/api/app/auth/me", provider: "Droid", headers: headers) { return auth }
        }
        return nil
    }

    private static func droidVersion() async -> String? {
        await Task.detached(priority: .utility) {
            let candidates = [SubscriptionCredentials.home.appendingPathComponent(".local/bin/droid").path, "/opt/homebrew/bin/droid", "/usr/local/bin/droid"]
            guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path); process.arguments = ["--version"]
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning && Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
            if process.isRunning { process.terminate(); return nil }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let output, output.count < 150, !output.isEmpty else { return nil }
            return output
        }.value
    }
}
