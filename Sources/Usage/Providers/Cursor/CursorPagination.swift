import Foundation

struct CursorPagination {
    let pageSize: Int
    var events: [JSON] = []
    private var expected: Int?
    private var previous: [Data] = []
    init(pageSize: Int) { self.pageSize = pageSize }
    mutating func append(_ page: CursorEventPage) throws -> Bool {
        if let total = page.total {
            if let expected, expected != total { throw SubscriptionError.message("Cursor's event count changed during refresh. Try again.") }
            expected = total
        }
        let keys = try page.events.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
        var overlap = 0
        if !previous.isEmpty && !keys.isEmpty {
            if previous == keys { throw SubscriptionError.message("Cursor repeated a usage page. Incomplete totals were not displayed.") }
            for count in 1...min(previous.count, keys.count) {
                if Array(previous.suffix(count)) == Array(keys.prefix(count)) { overlap = count }
            }
        }
        events.append(contentsOf: page.events.dropFirst(overlap))
        previous = keys
        let finished = page.events.count < pageSize
        if finished, let expected, events.count != expected {
            throw SubscriptionError.message("Cursor's usage report was incomplete. Try refreshing again.")
        }
        return finished
    }
}
