import Foundation

struct CursorEventPage {
    let total: Int?
    let events: [JSON]
    init(_ raw: JSON) throws {
        if raw.isEmpty { total = 0; events = []; return }
        if let n = number(raw["totalUsageEventsCount"]), n >= 0, n < Double(Int.max), n.rounded() == n { total = Int(n) }
        else if raw["totalUsageEventsCount"] == nil { total = nil }
        else { throw SubscriptionError.message("Cursor returned an invalid usage-event count.") }
        if let values = raw["usageEventsDisplay"] as? [JSON] { events = values }
        else if total == 0, raw.count == 1 { events = [] }
        else { throw SubscriptionError.message("Cursor did not return a valid usage-event page.") }
    }
}
