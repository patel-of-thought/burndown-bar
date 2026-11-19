import Foundation
import SQLite3

extension SubscriptionCredentials {
    struct CursorSession {
        let cookie: String
        let source: String
        let email: String?
    }
    static func cursor() async throws -> CursorSession {
        let source = UserDefaults.standard.string(forKey: "cursorSource") ?? "browser"
        if source == "browser" {
            do { return try await BrowserCursorSession.session() }
            catch { throw SubscriptionError.message(error.localizedDescription) }
        }
        if source != "desktop" {
            if let cookie = saved("cursor-cookie") {
                return CursorSession(cookie: cookie.contains("=") ? cookie : "WorkosCursorSessionToken=\(cookie)",
                                     source: "Manual Cursor cookie", email: nil)
            }
            throw SubscriptionError.message("Sign into Cursor in Connections, or select Manual cookie and paste your WorkosCursorSessionToken cookie.")
        }
        // The desktop database is read only when the user explicitly chooses that source.
        let path = home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
        if let token = sqliteValue(path: path, key: "cursorAuth/accessToken"), let payload = jwt(token),
           let subject = string(payload["sub"]), let id = subject.components(separatedBy: "|").last,
           !id.isEmpty, let expiration = date(payload["exp"]), expiration > Date() {
            return CursorSession(cookie: "WorkosCursorSessionToken=\(id)%3A%3A\(token)", source: "Cursor.app",
                                 email: sqliteValue(path: path, key: "cursorAuth/cachedEmail") ?? string(payload["email"]))
        }
        throw SubscriptionError.message("Sign into Cursor.app, or switch the Cursor source to Browser sign-in or Manual cookie.")
    }

    static func sqliteValue(path: String, key: String) -> String? {
        var database: OpaquePointer?
        // Read-only access includes Cursor's WAL and never updates its credential database.
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK else { if database != nil { sqlite3_close(database) }; return nil }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1000)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM ItemTable WHERE key = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }
}
