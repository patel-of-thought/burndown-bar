import Foundation
import Security
import CryptoKit

struct LocalAntigravityProcess {
    let pid: Int
    let csrf: String
    let extensionPort: Int?
    static func parse(_ output: String, uid: UInt32 = getuid()) -> [LocalAntigravityProcess] {
        let entries = output.split(separator: "\n").compactMap { line -> (uid: UInt32, pid: Int, parent: Int, command: String)? in
            let parts = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
            guard parts.count == 4, let user = UInt32(parts[0]), let pid = Int(parts[1]), let parent = Int(parts[2]) else { return nil }
            return (user, pid, parent, String(parts[3]))
        }
        let indexed = Dictionary(entries.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        return entries.compactMap { entry in
            let command = entry.command.lowercased()
            guard entry.uid == uid, command.contains("antigravity"), command.contains("language_server"),
                  !command.contains("codexbar"), command.contains("/antigravity.app/") else { return nil }
            var parent = entry.parent, visited = Set<Int>()
            while let ancestor = indexed[parent], visited.insert(parent).inserted {
                guard !ancestor.command.lowercased().contains("codexbar") else { return nil }
                parent = ancestor.parent
            }
            guard let token = flag("--csrf_token", in: entry.command), !token.isEmpty else { return nil }
            return LocalAntigravityProcess(pid: entry.pid, csrf: token, extensionPort: flag("--extension_server_port", in: entry.command).flatMap(Int.init))
        }
    }
    static func flag(_ key: String, in command: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: key) + #"(?:=|\s+)([^\s]+)"#),
              let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
              let range = Range(match.range(at: 1), in: command) else { return nil }
        return String(command[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}

private final class LocalAntigravityDelegate: NSObject, URLSessionTaskDelegate {
    let port: Int
    private var pin: Data?
    private let lock = NSLock()
    init(port: Int) { self.port = port }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.host == "127.0.0.1", space.port == port,
              space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            completionHandler(.performDefaultHandling, nil); return
        }
        // This delegate is created only for an owned, discovered Antigravity process port.
        // Its generated local certificate is pinned for this connection; no remote TLS policy changes.
        let fingerprint = Data(SHA256.hash(data: SecCertificateCopyData(leaf) as Data))
        lock.lock()
        let accepted = pin == nil || pin == fingerprint
        if pin == nil { pin = fingerprint }
        lock.unlock()
        completionHandler(accepted ? .useCredential : .cancelAuthenticationChallenge, accepted ? URLCredential(trust: trust) : nil)
    }
}

final class AntigravityLocalClient {
    func fetch() async throws -> Account {
        let processes = LocalAntigravityProcess.parse(try await Self.command("/bin/ps", ["-ax", "-o", "uid=,pid=,ppid=,command="]))
        guard !processes.isEmpty else {
            throw SubscriptionError.message("Open Antigravity and sign in. Its local service must be running to read usage.")
        }
        for process in processes.prefix(3) {
            let listing = try await Self.command("/usr/sbin/lsof", ["-nP", "-a", "-p", String(process.pid), "-iTCP", "-sTCP:LISTEN", "-Fn"])
            let ports = Self.ports(listing)
            for port in ports.prefix(5) {
                if let result = try? await fetch(port: port, csrf: process.csrf) { return result }
            }
        }
        throw SubscriptionError.message("Antigravity's local quota service did not respond. Reopen the app and refresh.")
    }
    private func fetch(port: Int, csrf: String) async throws -> Account {
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 2; settings.timeoutIntervalForResource = 3
        settings.connectionProxyDictionary = [:]; settings.urlCache = nil; settings.httpShouldSetCookies = false
        let delegate = LocalAntigravityDelegate(port: port)
        let session = URLSession(configuration: settings, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let base = "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/"
        @Sendable func call(_ method: String, body: JSON) async throws -> JSON {
            var request = URLRequest(url: URL(string: base + method)!)
            request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.setValue(csrf, forHTTPHeaderField: "X-Codeium-Csrf-Token")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let json = try JSONSerialization.jsonObject(with: data) as? JSON else { throw URLError(.badServerResponse) }
            return json
        }
        let metadata: JSON = ["metadata": ["ideName": "antigravity", "extensionName": "antigravity", "ideVersion": "unknown", "locale": "en"]]
        async let identity = try? call("GetUserStatus", body: metadata)
        var account: Account
        do { account = try AdditionalParsers.antigravity(await call("RetrieveUserQuotaSummary", body: ["forceRefresh": true])) }
        catch {
            guard let user = await identity else { throw error }
            account = try AdditionalParsers.antigravity(user)
        }
        if let identity = await identity, let user = identity["userStatus"] as? JSON {
            let original = account
            account = AdditionalParsers.withIdentity(account, email: string(user["email"]))
            account.windows = original.windows; account.updatedAt = original.updatedAt
            let info = ((user["planStatus"] as? JSON)?["planInfo"] as? JSON) ?? [:]
            account.plan = string(info["planDisplayName"] ?? info["planName"] ?? (user["userTier"] as? JSON)?["name"]) ?? original.plan
        }
        account.details = ProviderDetails(source: "Antigravity local API", version: SubscriptionClient.appVersion("/Applications/Antigravity.app"),
                                         dashboardURL: URL(string: AccountOrigin.antigravity.dashboard))
        return account
    }
    static func ports(_ listing: String) -> [Int] {
        Array(Set(listing.split(separator: "\n").compactMap { line -> Int? in
            guard line.hasPrefix("n"), let colon = line.lastIndex(of: ":"), let port = Int(line[line.index(after: colon)...]), (1024...65535).contains(port) else { return nil }
            return port
        })).sorted()
    }
    static func command(_ path: String, _ arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
            process.standardOutput = output; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
            try process.run()
            let cancellation = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: cancellation)
            defer { cancellation.cancel() }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard data.count < 4_000_000 else { throw SubscriptionError.message("The local process list was too large.") }
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}
