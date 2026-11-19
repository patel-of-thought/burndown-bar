import Foundation
import SQLite3

/// Reads the usage history CLIProxyAPI keeps in its own application-support folder.
/// Queries run against a temporary copy, so the originals are never opened for writing.
enum ProxyUsageReader {
    static let requestsTitle = "CLIProxyAPI requests"
    static let agentLogsTitle = "Local agent logs"

    static var directory: URL { ProxyConfiguration.fileURL.deletingLastPathComponent() }

    /// Agent-log source names used by CLIProxyAPI mapped to this app's provider names.
    private static let agentSources = [
        "codex": "Codex", "claude": "Claude", "opencode": "OpenCode", "antigravity": "Antigravity",
        "copilot": "Copilot", "gemini": "Gemini"
    ]

    /// Providers report input differently: OpenAI-style totals include cached tokens, Anthropic-style totals do not.
    /// A row whose total equals input + output already contains its cache tokens, so they are split out of input.
    private static let freshInput = """
        CASE WHEN total_tokens = input_tokens + output_tokens AND input_tokens >= cache_read_tokens + cache_creation_tokens \
        THEN input_tokens - cache_read_tokens - cache_creation_tokens ELSE input_tokens END
        """

    /// Series keyed by provider name. Missing databases or unexpected schemas simply produce no series.
    static func load(directory: URL = directory, now: Date = Date(), calendar: Calendar = .current,
                     days: Int = 30) -> [String: [UsageSeries]] {
        let today = calendar.startOfDay(for: now)
        guard let since = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [:] }
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let firstDay = formatter.string(from: since)

        var result = [String: [UsageSeries]]()
        func series(_ rows: [String: [String: DailyUsage]], id: String, title: String) {
            for (provider, byDay) in rows {
                let daily = (0..<days).compactMap { offset -> DailyUsage? in
                    guard let date = calendar.date(byAdding: .day, value: offset, to: since) else { return nil }
                    var usage = byDay[formatter.string(from: date)] ?? DailyUsage(date: date)
                    usage.date = date
                    return usage
                }
                let item = UsageSeries(id: id, title: title, daily: daily, hasCost: false)
                if item.hasData { result[provider, default: []].append(item) }
            }
        }

        series(query(directory.appendingPathComponent("usage-records/usage.db"), firstDay, """
            SELECT provider, substr(local_hour, 1, 10) AS day, SUM(\(freshInput)), SUM(output_tokens),
                   SUM(cache_read_tokens), SUM(cache_creation_tokens)
            FROM usage_events WHERE failed = 0 AND day >= ?1 GROUP BY provider, day
            """, name: Account.providerName(for:)), id: "proxy-requests", title: requestsTitle)
        series(query(directory.appendingPathComponent("agent-usage/agent_usage.db"), firstDay, """
            SELECT source, day, SUM(\(freshInput)), SUM(output_tokens), SUM(cache_read_tokens), SUM(cache_creation_tokens)
            FROM agent_usage_daily WHERE day >= ?1 GROUP BY source, day
            """, name: { agentSources[$0] }), id: "agent-logs", title: agentLogsTitle)
        return result
    }

    /// Returns provider name → day string → usage. Rows for unknown providers are skipped.
    private static func query(_ file: URL, _ firstDay: String, _ sql: String, name: (String) -> String?) -> [String: [String: DailyUsage]] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        // The proxy app keeps these in WAL mode, which a read-only connection cannot open while the app is idle.
        // Querying a private copy (with any write-ahead log) leaves the originals untouched.
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("easycli-usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let copy = scratch.appendingPathComponent(file.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.copyItem(at: file, to: copy)
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: file.path + suffix)
                if FileManager.default.fileExists(atPath: sidecar.path) {
                    try? FileManager.default.copyItem(at: sidecar, to: URL(fileURLWithPath: copy.path + suffix))
                }
            }
        } catch { return [:] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else { sqlite3_close(db); return [:] }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [:] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, firstDay, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var rows = [String: [String: DailyUsage]]()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawProvider = sqlite3_column_text(statement, 0), let rawDay = sqlite3_column_text(statement, 1),
                  let provider = name(String(cString: rawProvider)) else { continue }
            let day = String(cString: rawDay)
            var usage = rows[provider]?[day] ?? DailyUsage(date: Date(timeIntervalSince1970: 0))
            usage.input &+= max(0, sqlite3_column_int64(statement, 2))
            usage.output &+= max(0, sqlite3_column_int64(statement, 3))
            usage.cacheRead &+= max(0, sqlite3_column_int64(statement, 4))
            usage.cacheWrite &+= max(0, sqlite3_column_int64(statement, 5))
            rows[provider, default: [:]][day] = usage
        }
        return rows
    }
}
