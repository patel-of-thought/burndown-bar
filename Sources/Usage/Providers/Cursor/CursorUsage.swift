import Foundation

extension SubscriptionClient {
    func cursorCosts(headers: [String: String], now: Date = Date()) async throws -> UsageCosts {
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!
        var paging = CursorPagination(pageSize: 1000)
        for page in 1...50 {
            let body: JSON = ["page": page, "pageSize": 1000,
                "startDate": String(Int64(since.timeIntervalSince1970 * 1000)), "endDate": String(Int64(now.timeIntervalSince1970 * 1000))]
            let raw = try await request(url: "https://cursor.com/api/dashboard/get-filtered-usage-events", provider: "Cursor", headers: headers, body: body)
            if try paging.append(CursorEventPage(raw)) {
                return SubscriptionParser.costs(events: paging.events, now: now, calendar: calendar)
            }
        }
        throw SubscriptionError.message("The 30-day report exceeds the page limit. Incomplete totals were not displayed.")
    }
}
