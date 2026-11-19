import Foundation

enum QuotaParser {}

enum SubscriptionParser {}

enum AdditionalParsers {
    static func firstNumber(_ raw: JSON, keys: [String]) -> Double? { keys.lazy.compactMap { number(raw[$0]) }.first }
    static func firstDate(_ raw: JSON, keys: [String]) -> Date? { keys.lazy.compactMap { date(raw[$0]) }.first }
    static func withIdentity(_ account: Account, email: String?) -> Account {
        guard let email else { return account }
        var result = Account(id: account.id, name: account.name, email: email, provider: account.provider, authIndex: account.authIndex,
            accountID: account.accountID, disabled: account.disabled, plan: account.plan, origin: account.origin)
        result.details = account.details; result.costs = account.costs; result.openRouter = account.openRouter
        result.windows = account.windows; result.credits = account.credits; result.facts = account.facts
        result.error = account.error; result.updatedAt = account.updatedAt
        return result
    }
}
