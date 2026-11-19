import Foundation

extension QuotaParser {
    static func claude(_ data: JSON) -> [QuotaWindow] {
        let fields: [(String, String, Double)] = [("five_hour", "5-hour", 18000), ("seven_day", "Weekly", 604800),
            ("seven_day_opus", "Opus weekly", 604800), ("seven_day_sonnet", "Sonnet weekly", 604800)]
        return fields.compactMap { key, title, period in
            guard let window = data[key] as? JSON else { return nil }
            return QuotaWindow(id: key, title: title,
                remaining: number(window["utilization"]).map { max(0, min(100, 100 - $0)) },
                reset: date(window["resets_at"]), period: period)
        }
    }
}
