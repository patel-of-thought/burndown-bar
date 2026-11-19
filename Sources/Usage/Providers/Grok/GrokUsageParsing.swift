import Foundation

extension AdditionalParsers {
    static func grok(_ raw: JSON) throws -> Account {
        let billing = GrokBilling.parse([raw["config"] as? JSON ?? raw])
        guard !billing.windows.isEmpty || billing.balanceUSD != nil else { throw SubscriptionError.message("Grok did not report a billing allowance.") }
        var account = SubscriptionClient.placeholder(.grok)
        account.windows = billing.windows; account.plan = billing.plan ?? "Grok subscription"
        account.details?.extraBalanceUSD = billing.balanceUSD
        return account
    }
}
