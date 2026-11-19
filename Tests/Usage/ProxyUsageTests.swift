import Foundation
import SQLite3

enum ProxyUsageTests {
    static func run() -> Int {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
            passed += 1
        }
        func execute(_ file: URL, _ statements: [String]) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var db: OpaquePointer?
            guard sqlite3_open(file.path, &db) == SQLITE_OK else { fputs("FAIL: fixture database\n", stderr); exit(1) }
            defer { sqlite3_close(db) }
            for statement in statements where sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
                fputs("FAIL: fixture SQL \(statement)\n", stderr); exit(1)
            }
        }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2026-11-15T12:00:00Z")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("easycli-proxy-usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        check(ProxyUsageReader.load(directory: root, now: now, calendar: utc).isEmpty, "missing proxy databases produce no usage")

        let events = "CREATE TABLE usage_events (provider TEXT, local_hour TEXT, failed INTEGER, total_tokens INTEGER, input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER, cache_creation_tokens INTEGER)"
        execute(root.appendingPathComponent("usage-records/usage.db"), [events,
            "INSERT INTO usage_events VALUES ('codex', '2026-11-15-09', 0, 1050, 1000, 50, 800, 0)",
            "INSERT INTO usage_events VALUES ('codex', '2026-11-15-10', 0, 1050, 1000, 50, 800, 0)",
            "INSERT INTO usage_events VALUES ('codex', '2026-11-15-11', 1, 9999, 9000, 999, 0, 0)",
            "INSERT INTO usage_events VALUES ('codex', '2026-09-01-11', 0, 5000, 4000, 1000, 0, 0)",
            "INSERT INTO usage_events VALUES ('claude', '2026-11-14-08', 0, 650, 100, 10, 500, 40)"])
        execute(root.appendingPathComponent("agent-usage/agent_usage.db"), [
            "CREATE TABLE agent_usage_daily (source TEXT, day TEXT, total_tokens INTEGER, input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER, cache_creation_tokens INTEGER)",
            "INSERT INTO agent_usage_daily VALUES ('codex', '2026-11-13', 330, 100, 30, 200, 0)",
            "INSERT INTO agent_usage_daily VALUES ('codex', '2026-11-13', 70, 50, 20, 0, 0)",
            "INSERT INTO agent_usage_daily VALUES ('kimi', '2026-11-13', 70, 50, 20, 0, 0)"])

        let usage = ProxyUsageReader.load(directory: root, now: now, calendar: utc)
        let codex = usage["Codex"] ?? []
        check(codex.map(\.title) == [ProxyUsageReader.requestsTitle, ProxyUsageReader.agentLogsTitle], "proxy requests and agent logs are separate sources")
        check(codex.allSatisfy { !$0.hasCost && $0.daily.count == 30 }, "proxy usage has 30 days and no invented cost")
        let today = codex.first?.daily.last
        check(today.map { [$0.input, $0.output, $0.cacheRead, $0.cacheWrite] } == [400, 100, 1600, 0],
              "cached tokens are split out of OpenAI-style input; failed requests are ignored")
        check(codex.first?.daily.reduce(0, { $0 + $1.tokens }) == 2100, "requests older than 30 days are excluded")
        let claude = usage["Claude"]?.first?.daily.dropLast().last
        check(claude.map { [$0.input, $0.output, $0.cacheRead, $0.cacheWrite] } == [100, 10, 500, 40], "Anthropic-style input is not reduced by cache tokens")
        let agent = codex.last?.daily.first { $0.date == date("2026-11-13T00:00:00Z") }
        check(agent.map { [$0.input, $0.output, $0.cacheRead] } == [150, 50, 200], "agent log rows for a day are summed")
        check(usage["Kimi"] == nil, "unsupported agent sources are skipped")

        execute(root.appendingPathComponent("usage-records/usage.db"), ["DROP TABLE usage_events", "CREATE TABLE usage_events (id INTEGER)"])
        check(ProxyUsageReader.load(directory: root, now: now, calendar: utc)["Codex"]?.count == 1, "unexpected proxy schema is ignored without affecting other sources")
        return passed
    }
}
