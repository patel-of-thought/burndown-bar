import AppKit
import CommonCrypto
import LocalAuthentication
import Security
import SQLite3

/// Reads only Cursor's session cookie, from the browser macOS actually opens for HTTPS.
/// Browser databases stay read-only; decrypted values are never written to disk or logged.
enum BrowserCursorSession {
    static let cookieName = "WorkosCursorSessionToken"
    private static let keyLock = NSLock()
    private static var unlockedKeys: [String: Data] = [:]

    enum ReadError: LocalizedError {
        case signedOut(String)
        case unavailable(String)
        var errorDescription: String? {
            switch self {
            case .signedOut(let name): return "Sign into cursor.com in \(name)'s current profile, then refresh. Private browsing sessions cannot be imported."
            case .unavailable(let message): return message
            }
        }
    }

    struct Browser {
        enum Storage { case chromium(String), firefox, safari }
        let name: String
        let directory: URL
        let storage: Storage

        static func configuration(bundleID: String, home: URL) -> Browser? {
            let support = home.appendingPathComponent("Library/Application Support")
            let chromium: [String: (String, String, String)] = [
                "com.google.chrome": ("Chrome", "Google/Chrome", "Chrome Safe Storage"),
                "com.google.chrome.beta": ("Chrome Beta", "Google/Chrome Beta", "Chrome Safe Storage"),
                "com.google.chrome.dev": ("Chrome Dev", "Google/Chrome Dev", "Chrome Safe Storage"),
                "com.google.chrome.canary": ("Chrome Canary", "Google/Chrome Canary", "Chrome Safe Storage"),
                "org.chromium.chromium": ("Chromium", "Chromium", "Chromium Safe Storage"),
                "com.brave.browser": ("Brave", "BraveSoftware/Brave-Browser", "Brave Safe Storage"),
                "com.microsoft.edgemac": ("Edge", "Microsoft Edge", "Microsoft Edge Safe Storage"),
                "company.thebrowser.browser": ("Arc", "Arc/User Data", "Arc Safe Storage"),
                "com.vivaldi.vivaldi": ("Vivaldi", "Vivaldi", "Vivaldi Safe Storage"),
                "com.operasoftware.opera": ("Opera", "com.operasoftware.Opera", "Opera Safe Storage"),
                "ai.perplexity.comet": ("Comet", "Comet", "Comet Safe Storage")
            ]
            let id = bundleID.lowercased()
            if let (name, directory, key) = chromium[id] {
                return Browser(name: name, directory: support.appendingPathComponent(directory), storage: .chromium(key))
            }
            if id == "org.mozilla.firefox" || id == "org.mozilla.firefoxdeveloperedition" {
                return Browser(name: "Firefox", directory: support.appendingPathComponent("Firefox"), storage: .firefox)
            }
            if id == "com.apple.safari" {
                return Browser(name: "Safari", directory: home.appendingPathComponent("Library"), storage: .safari)
            }
            return nil
        }
    }

    static func session(allowInteraction: Bool = false) async throws -> SubscriptionCredentials.CursorSession {
        let browser = try await MainActor.run { () throws -> Browser in
            guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://cursor.com")!),
                  let bundle = Bundle(url: app), let id = bundle.bundleIdentifier else {
                throw ReadError.unavailable("Could not identify your default browser. Select Manual cookie in Connections to connect Cursor.")
            }
            guard let browser = Browser.configuration(bundleID: id, home: SubscriptionCredentials.home) else {
                throw ReadError.unavailable("Automatic Cursor cookies are not supported for \(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "this browser"). Select Manual cookie in Connections.")
            }
            return browser
        }
        return try await Task.detached(priority: .utility) {
            let cookie = try read(browser, allowInteraction: allowInteraction)
            return SubscriptionCredentials.CursorSession(cookie: cookie, source: "Default browser · \(browser.name)", email: nil)
        }.value
    }

    static func read(_ browser: Browser, allowInteraction: Bool, now: Date = Date()) throws -> String {
        switch browser.storage {
        case .chromium(let service):
            let profile = try chromiumProfile(browser.directory)
            let paths = [profile.appendingPathComponent("Network/Cookies"), profile.appendingPathComponent("Cookies")]
            guard let file = paths.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                throw ReadError.signedOut(browser.name)
            }
            return try chromium(file: file, now: now) { try storageKey(service: service, browser: browser.name, allowInteraction: allowInteraction) }
        case .firefox:
            let profile = try firefoxProfile(browser.directory)
            return try firefox(file: profile.appendingPathComponent("cookies.sqlite"), now: now)
        case .safari:
            let files = ["Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies", "Cookies/Cookies.binarycookies"]
            var denied = false
            for relative in files {
                do {
                    let data = try Data(contentsOf: browser.directory.appendingPathComponent(relative))
                    if let value = try safari(data: data, now: now) { return value }
                } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { continue }
                catch { denied = true }
            }
            if denied { throw ReadError.unavailable("Safari's cookies could not be read. Allow BurndownBar in System Settings → Privacy & Security → Full Disk Access, then reopen it, or use Manual cookie.") }
            throw ReadError.signedOut(browser.name)
        }
    }

    // Use the last-used profile only. Never silently connect a different browser profile's account.
    static func chromiumProfile(_ directory: URL) throws -> URL {
        let state = directory.appendingPathComponent("Local State")
        var profile = "Default"
        if FileManager.default.fileExists(atPath: state.path) {
            do {
                let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: state)) as? [String: Any]
                if let last = (raw?["profile"] as? [String: Any])?["last_used"] as? String, !last.isEmpty { profile = last }
            } catch { throw ReadError.unavailable("Could not read the default browser's current profile. Reopen the browser and try again, or use Manual cookie.") }
        }
        guard profile != ".", profile != "..", !profile.contains("/"), !profile.contains("\\") else {
            throw ReadError.unavailable("The default browser reported an invalid profile directory.")
        }
        // Opera stores its database directly in its support directory.
        if !FileManager.default.fileExists(atPath: state.path), FileManager.default.fileExists(atPath: directory.appendingPathComponent("Cookies").path) { return directory }
        return directory.appendingPathComponent(profile)
    }

    static func firefoxProfile(_ directory: URL) throws -> URL {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("profiles.ini"), encoding: .utf8) else {
            throw ReadError.unavailable("Could not read Firefox's profiles. Open Firefox and sign into Cursor, or use Manual cookie.")
        }
        var sections: [[String: String]] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { sections.append(["section": line]); continue }
            guard !sections.isEmpty, !line.hasPrefix(";"), let equals = line.firstIndex(of: "=") else { continue }
            sections[sections.count - 1][String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        let installs = sections.filter { $0["section"]?.hasPrefix("[Install") == true }.compactMap { $0["Default"] }
        let profiles = sections.filter { $0["section"]?.hasPrefix("[Profile") == true }
        let selected: String
        let relative: Bool
        if Set(installs).count == 1, let path = installs.first { selected = path; relative = true }
        else if let profile = profiles.first(where: { $0["Default"] == "1" }), let path = profile["Path"] {
            selected = path; relative = profile["IsRelative"] != "0"
        } else if profiles.count == 1, let path = profiles.first?["Path"] {
            selected = path; relative = profiles.first?["IsRelative"] != "0"
        } else { throw ReadError.unavailable("Firefox has multiple profiles with no unambiguous default. Use Manual cookie for the Cursor account you want.") }
        return relative ? directory.appendingPathComponent(selected) : URL(fileURLWithPath: selected)
    }

    private static func database<T>(_ file: URL, _ operation: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw ReadError.unavailable("Could not read the browser's cookie database. Quit and reopen the browser, or allow BurndownBar access in macOS Privacy & Security. Manual cookie is also available.")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)
        return try operation(db)
    }

    private static func query<T>(_ db: OpaquePointer, _ sql: String, _ operation: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw ReadError.unavailable("The browser's cookie format is not supported. Use Manual cookie in Connections.")
        }
        defer { sqlite3_finalize(statement) }
        return try operation(statement)
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    static func chromium(file: URL, now: Date, key: () throws -> Data) throws -> String {
        try database(file) { db in
            let version = try query(db, "SELECT value FROM meta WHERE key = 'version'") { s in
                sqlite3_step(s) == SQLITE_ROW ? Int(text(s, 0)) ?? 0 : 0
            }
            let columns = try query(db, "PRAGMA table_info(cookies)") { s -> Set<String> in
                var names = Set<String>()
                while sqlite3_step(s) == SQLITE_ROW { names.insert(text(s, 1)) }
                return names
            }
            let partition = columns.contains("top_frame_site_key") ? " AND top_frame_site_key = ''" : ""
            return try query(db, "SELECT host_key, value, encrypted_value, expires_utc FROM cookies WHERE name = '\(cookieName)' AND host_key IN ('cursor.com', '.cursor.com') AND path = '/'\(partition) ORDER BY last_access_utc DESC") { s in
                var result: Int32
                var derivedKey: Data?
                repeat {
                    result = sqlite3_step(s)
                    guard result == SQLITE_ROW else { break }
                    let expires = sqlite3_column_double(s, 3)
                    guard expires == 0 || expires / 1_000_000 - 11_644_473_600 > now.timeIntervalSince1970 else { continue }
                    var value = text(s, 1)
                    if let bytes = sqlite3_column_blob(s, 2), sqlite3_column_bytes(s, 2) > 0 {
                        if derivedKey == nil { derivedKey = try key() }
                        value = try decrypt(Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, 2))), key: derivedKey!, host: text(s, 0), version: version)
                    }
                    if let header = header(value) { return header }
                } while result == SQLITE_ROW
                guard result == SQLITE_DONE else { throw ReadError.unavailable("The browser's cookies are busy. Close the browser and refresh again.") }
                throw ReadError.signedOut("your default browser")
            }
        }
    }

    static func firefox(file: URL, now: Date) throws -> String {
        try database(file) { db in
            try query(db, "SELECT value, expiry FROM moz_cookies WHERE name = '\(cookieName)' AND host IN ('cursor.com', '.cursor.com') AND path = '/' AND originAttributes = '' ORDER BY lastAccessed DESC") { s in
                var result: Int32
                repeat {
                    result = sqlite3_step(s)
                    guard result == SQLITE_ROW else { break }
                    let expires = sqlite3_column_double(s, 1)
                    if expires > now.timeIntervalSince1970, let header = header(text(s, 0)) { return header }
                } while result == SQLITE_ROW
                guard result == SQLITE_DONE else { throw ReadError.unavailable("Firefox's cookies are busy. Close Firefox and refresh again.") }
                throw ReadError.signedOut("Firefox")
            }
        }
    }

    static func header(_ value: String) -> String? {
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 > 0x20 && $0 < 0x7f && $0 != 0x3b }) else { return nil }
        return "\(cookieName)=\(value)"
    }

    private static func storageKey(service: String, browser: String, allowInteraction: Bool) throws -> Data {
        // A one-time Keychain allowance is enough for this app run. Cookies themselves
        // are still read afresh; only the browser's derived encryption key is retained.
        keyLock.lock()
        let unlocked = unlockedKeys[service]
        keyLock.unlock()
        if let unlocked { return unlocked }
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: context]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let password = item as? Data else {
            throw ReadError.unavailable("Allow BurndownBar to read “\(service)” in Keychain to import \(browser)'s Cursor cookie. Choose Connect from default browser in Connections to retry, or select Manual cookie.")
        }
        let key = try deriveKey(password)
        keyLock.lock()
        unlockedKeys[service] = key
        keyLock.unlock()
        return key
    }

    static func deriveKey(_ password: Data) throws -> Data {
        var output = Data(count: kCCKeySizeAES128)
        let salt = Data("saltysalt".utf8)
        let status = output.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { secret in
                salt.withUnsafeBytes { salt in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), secret.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                        salt.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        out.baseAddress?.assumingMemoryBound(to: UInt8.self), out.count)
                }
            }
        }
        guard status == kCCSuccess else { throw ReadError.unavailable("Could not unlock the browser cookie. Use Manual cookie.") }
        return output
    }

    static func decrypt(_ encrypted: Data, key: Data, host: String, version: Int) throws -> String {
        guard encrypted.starts(with: Data("v10".utf8)), key.count == kCCKeySizeAES128 else {
            throw ReadError.unavailable("The browser uses an unsupported cookie encryption format. Use Manual cookie in Connections.")
        }
        let ciphertext = Data(encrypted.dropFirst(3))
        var plaintext = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var written = 0
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        let capacity = plaintext.count
        let status = plaintext.withUnsafeMutableBytes { output in
            ciphertext.withUnsafeBytes { input in
                key.withUnsafeBytes { key in
                    iv.withUnsafeBytes { iv in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                key.baseAddress, key.count, iv.baseAddress, input.baseAddress, input.count, output.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw ReadError.unavailable("Could not decrypt the browser's Cursor cookie. Reconnect in Connections, or use Manual cookie.") }
        plaintext.count = written
        if version >= 24 {
            let digest = sha256(Data(host.utf8))
            guard plaintext.starts(with: digest) else { throw ReadError.unavailable("The browser cookie failed its domain check. Use Manual cookie.") }
            plaintext = Data(plaintext.dropFirst(digest.count))
        }
        guard let value = String(data: plaintext, encoding: .utf8) else { throw ReadError.unavailable("The browser returned an invalid Cursor cookie.") }
        return value
    }

    static func sha256(_ data: Data) -> Data {
        var digest = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        digest.withUnsafeMutableBytes { output in
            data.withUnsafeBytes { input in _ = CC_SHA256(input.baseAddress, CC_LONG(input.count), output.baseAddress?.assumingMemoryBound(to: UInt8.self)) }
        }
        return digest
    }

    // Safari's binarycookie file uses big-endian page sizes and little-endian records.
    static func safari(data: Data, now: Date) throws -> String? {
        func invalid() -> ReadError { .unavailable("Safari's cookie file could not be read. Use Manual cookie in Connections.") }
        func uint(_ bytes: Data, _ offset: Int, big: Bool = false) throws -> Int {
            guard offset >= 0, bytes.count >= 4, offset <= bytes.count - 4 else { throw invalid() }
            let part = bytes[offset..<(offset + 4)]
            return big ? part.reduce(0) { ($0 << 8) | Int($1) } : part.reversed().reduce(0) { ($0 << 8) | Int($1) }
        }
        func cstring(_ bytes: Data, _ offset: Int) throws -> String {
            guard offset >= 56, offset < bytes.count, let end = bytes[offset...].firstIndex(of: 0),
                  let value = String(data: bytes[offset..<end], encoding: .utf8) else { throw invalid() }
            return value
        }
        guard data.starts(with: Data("cook".utf8)) else { throw invalid() }
        let count = try uint(data, 4, big: true)
        guard count <= (data.count - 8) / 4 else { throw invalid() }
        var pageOffset = 8 + count * 4
        for index in 0..<count {
            let size = try uint(data, 8 + index * 4, big: true)
            guard pageOffset <= data.count, size <= data.count - pageOffset else { throw invalid() }
            let page = Data(data[pageOffset..<(pageOffset + size)])
            pageOffset += size
            guard page.starts(with: Data([0, 0, 1, 0])) else { throw invalid() }
            let cookies = try uint(page, 4)
            guard cookies <= max(0, (page.count - 8) / 4) else { throw invalid() }
            for cookie in 0..<cookies {
                let offset = try uint(page, 8 + cookie * 4)
                let recordSize = try uint(page, offset)
                guard recordSize >= 56, offset <= page.count, recordSize <= page.count - offset else { throw invalid() }
                let record = Data(page[offset..<(offset + recordSize)])
                let host = try cstring(record, uint(record, 16))
                guard host == "cursor.com" || host == ".cursor.com" else { continue }
                guard try cstring(record, uint(record, 20)) == cookieName, try cstring(record, uint(record, 24)) == "/" else { continue }
                let bits = record[40..<48].reversed().reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                let expires = Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
                guard expires > now else { continue }
                if let header = header(try cstring(record, uint(record, 28))) { return header }
            }
        }
        return nil
    }
}
