import Foundation
import SQLite3

enum BrowserCursorSessionTests {
    static func run() -> Int {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fputs("FAIL: \(label)\n", stderr); exit(1) }; checks += 1
        }
        func rejected(_ label: String, _ body: () throws -> Void) {
            do { try body(); check(false, label) } catch { check(true, label) }
        }
        func hex(_ text: String) -> Data {
            let chars = Array(text)
            return Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...($0 + 1)]), radix: 16)! })
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("easycli-browser-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expected = "WorkosCursorSessionToken=fixture-session"
        let key = try! BrowserCursorSession.deriveKey(Data("fixture-password".utf8))
        // Golden vectors generated independently with Python hashlib and OpenSSL AES-CBC.
        check(key == hex("5d84e88b8d2628e23102b464d77a5bbd"), "browser PBKDF2 matches independent vector")
        let legacy = hex("76313030257076efa3a02cc9d30737956092ba")
        let modern = hex("7631307acbf441aa3d0d38477ea5f7a5be019b7fba8d4d7c1cb75d5dc9ce8b7da52fd5213cc0a6b8b865d54ae0719a2e667511")
        let legacyValue = try! BrowserCursorSession.decrypt(legacy, key: key, host: ".cursor.com", version: 23)
        let modernValue = try! BrowserCursorSession.decrypt(modern, key: key, host: ".cursor.com", version: 24)
        check(legacyValue == "fixture-session" && modernValue == legacyValue, "legacy and domain-bound Chromium cookies decrypt")
        rejected("Chromium domain digest is verified") { _ = try BrowserCursorSession.decrypt(modern, key: key, host: "cursor.com", version: 24) }
        rejected("unsupported encryption never becomes a token") { _ = try BrowserCursorSession.decrypt(Data("v20fixture".utf8), key: key, host: ".cursor.com", version: 24) }
        rejected("truncated encrypted cookie fails") { _ = try BrowserCursorSession.decrypt(Data("v10".utf8), key: key, host: ".cursor.com", version: 24) }
        check(BrowserCursorSession.header("abc%3A%3Atoken==") == "WorkosCursorSessionToken=abc%3A%3Atoken==", "session encoding is preserved")
        check(["", "a\r\nb", "a;b=c", "a\0b", "a b"].allSatisfy { BrowserCursorSession.header($0) == nil }, "browser cookie rejects control characters and header injection")

        let chrome = BrowserCursorSession.Browser.configuration(bundleID: "com.google.Chrome", home: root)!
        check(chrome.name == "Chrome" && chrome.directory.path.hasSuffix("Google/Chrome"), "default browser maps to its own cookie store")
        check(BrowserCursorSession.Browser.configuration(bundleID: "unknown.browser", home: root) == nil, "unknown browser does not fall back to another account")
        check(try! BrowserCursorSession.chromiumProfile(root).lastPathComponent == "Default", "Chromium initial profile")
        let localState = root.appendingPathComponent("Local State")
        try! Data(#"{"profile":{"last_used":"Profile 2"}}"#.utf8).write(to: localState)
        check(try! BrowserCursorSession.chromiumProfile(root).lastPathComponent == "Profile 2", "Chromium follows last-used profile rather than scanning other accounts")
        try! Data(#"{"profile":{"last_used":"../other"}}"#.utf8).write(to: localState)
        rejected("invalid Chromium profile path rejected") { _ = try BrowserCursorSession.chromiumProfile(root) }
        try! Data("[InstallFixture]\nDefault=Profiles/active\n[Profile0]\nPath=Profiles/old\nDefault=1\nIsRelative=1\n".utf8).write(to: root.appendingPathComponent("profiles.ini"))
        check(try! BrowserCursorSession.firefoxProfile(root).path == root.appendingPathComponent("Profiles/active").path, "Firefox install default takes precedence over old profile")
        try! Data("[Profile0]\nPath=Profiles/one\n[Profile1]\nPath=Profiles/two\n".utf8).write(to: root.appendingPathComponent("profiles.ini"))
        rejected("ambiguous Firefox accounts are not guessed") { _ = try BrowserCursorSession.firefoxProfile(root) }

        let dbFile = root.appendingPathComponent("Cookies")
        var db: OpaquePointer?
        check(sqlite3_open(dbFile.path, &db) == SQLITE_OK, "fixture database opens")
        defer { sqlite3_close(db) }
        func sql(_ text: String) { check(sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK, "browser fixture SQL") }
        sql("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE meta(key TEXT, value TEXT); INSERT INTO meta VALUES ('version','24'); CREATE TABLE cookies(host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, expires_utc INTEGER, path TEXT, last_access_utc INTEGER, top_frame_site_key TEXT);")
        let future = Int64((now.timeIntervalSince1970 + 11_644_473_600 + 3600) * 1_000_000)
        let past = future - 7_200_000_000
        sql("INSERT INTO cookies VALUES ('.cursor.com','WorkosCursorSessionToken','',X'\(modern.map { String(format: "%02x", $0) }.joined())',\(future), '/',1,'');")
        sql("INSERT INTO cookies VALUES ('cursor.com.evil.test','WorkosCursorSessionToken','foreign',X'',\(future),'/',9,''),('cursor.com','unrelated','other',X'',\(future),'/',9,''),('cursor.com','WorkosCursorSessionToken','expired',X'',\(past),'/',10,''),('cursor.com','WorkosCursorSessionToken','partitioned',X'',\(future),'/',11,'https://example.test'),('cursor.com','WorkosCursorSessionToken','wrong-path',X'',\(future),'/other',12,'');")
        var keyReads = 0
        let imported = try! BrowserCursorSession.chromium(file: dbFile, now: now) { keyReads += 1; return key }
        check(imported == expected && keyReads == 1, "read-only Chromium import reads live WAL and filters foreign, expired, partitioned and wrong-path cookies")
        sql("UPDATE cookies SET encrypted_value=X'', value='rotated-session' WHERE host_key='.cursor.com';")
        let rotated = try! BrowserCursorSession.chromium(file: dbFile, now: now) { fatalError("plaintext cookie should not query Keychain") }
        check(rotated == "WorkosCursorSessionToken=rotated-session", "refresh imports rotated cookies without stale saved credentials")
        sql("DELETE FROM cookies WHERE host_key='.cursor.com';")
        rejected("no valid Cursor session is not a successful import") { _ = try BrowserCursorSession.chromium(file: dbFile, now: now) { fatalError("irrelevant cookies must not query Keychain") } }
        sql("CREATE TABLE moz_cookies(host TEXT, name TEXT, value TEXT, expiry INTEGER, path TEXT, lastAccessed INTEGER, originAttributes TEXT); INSERT INTO moz_cookies VALUES ('.cursor.com','WorkosCursorSessionToken','fixture-session',1800003600,'/',1,''),('cursor.com','WorkosCursorSessionToken','container',1800003600,'/',9,'^userContextId=2'),('cursor.com','WorkosCursorSessionToken','expired',1799990000,'/',10,'');")
        let firefox = try! BrowserCursorSession.firefox(file: dbFile, now: now)
        check(firefox == expected, "Firefox imports session and excludes containers and expired cookies")

        func safariFile(host: String = ".cursor.com", value: String = "fixture-session", expires: Date? = nil) -> Data {
            func uint(_ value: Int, big: Bool = false) -> Data {
                let shifts = big ? [24, 16, 8, 0] : [0, 8, 16, 24]
                return Data(shifts.map { UInt8(truncatingIfNeeded: value >> $0) })
            }
            var record = Data(count: 56)
            for (slot, string) in [(16, host), (20, "WorkosCursorSessionToken"), (24, "/"), (28, value)] {
                record.replaceSubrange(slot..<(slot + 4), with: uint(record.count))
                record.append(Data(string.utf8)); record.append(0)
            }
            record.replaceSubrange(0..<4, with: uint(record.count))
            let bits = (expires ?? now.addingTimeInterval(3600)).timeIntervalSinceReferenceDate.bitPattern
            record.replaceSubrange(40..<48, with: Data((0..<8).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }))
            var page = Data([0, 0, 1, 0])
            page.append(uint(1)); page.append(uint(16)); page.append(uint(0)); page.append(record)
            var file = Data("cook".utf8)
            file.append(uint(1, big: true)); file.append(uint(page.count, big: true)); file.append(page)
            return file
        }
        let safari = safariFile()
        check(try! BrowserCursorSession.safari(data: safari, now: now) == expected, "Safari binary cookie import")
        check(try! BrowserCursorSession.safari(data: safariFile(host: "cursor.com.evil.test"), now: now) == nil, "Safari rejects lookalike domain")
        check(try! BrowserCursorSession.safari(data: safariFile(expires: now.addingTimeInterval(-1)), now: now) == nil, "Safari rejects expired session")
        var safelyRejected = true
        for count in 0..<safari.count {
            do { _ = try BrowserCursorSession.safari(data: Data(safari.prefix(count)), now: now); safelyRejected = false }
            catch { }
        }
        check(safelyRejected, "truncated Safari records fail safely at every byte boundary")
        print("Browser cookie fixtures passed: \(checks)")
        return checks
    }
}
