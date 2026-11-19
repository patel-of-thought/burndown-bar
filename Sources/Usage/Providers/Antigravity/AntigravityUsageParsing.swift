import Foundation

extension AdditionalParsers {
    static func antigravity(_ raw: JSON, now: Date = Date()) throws -> Account {
        if let code = raw["code"], !["0", "ok", "success"].contains((string(code) ?? "").lowercased()) {
            throw SubscriptionError.message("Antigravity rejected the quota request.")
        }
        var account = SubscriptionClient.placeholder(.antigravity)
        let user = raw["userStatus"] as? JSON ?? [:]
        account = withIdentity(account, email: string(user["email"]))
        let planInfo = ((user["planStatus"] as? JSON)?["planInfo"] as? JSON) ?? [:]
        account.plan = string(planInfo["planDisplayName"] ?? planInfo["displayName"] ?? planInfo["planName"] ?? (user["userTier"] as? JSON)?["name"]) ?? "Antigravity"
        let summary = raw["response"] as? JSON ?? raw["summary"] as? JSON ?? raw
        for (g, group) in (summary["groups"] as? [JSON] ?? []).enumerated() {
            let groupName = string(group["displayName"] ?? group["name"]) ?? "Quota"
            for (b, bucket) in (group["buckets"] as? [JSON] ?? []).enumerated() {
                let nested = bucket["remaining"] as? JSON ?? [:]
                let fraction = number(bucket["remainingFraction"] ?? bucket["remaining_fraction"] ?? nested["remainingFraction"]
                    ?? (string(nested["case"]) == "remainingFraction" ? nested["value"] : nil))
                let disabled = bucket["disabled"] as? Bool == true
                let label = string(bucket["displayName"] ?? bucket["display_name"] ?? bucket["window"]) ?? "Allowance"
                let cadence = string(bucket["window"])?.lowercased() ?? label.lowercased()
                let duration: Double? = cadence.contains("week") ? 604800 : cadence.contains("day") ? 86400 : cadence.contains("5") ? 18000 : nil
                account.windows.append(QuotaWindow(id: "ag-\(g)-\(b)", title: "\(groupName) · \(label)", remaining: disabled ? nil : fraction.map { max(0, min(100, $0 * 100)) },
                                                  reset: date(bucket["resetTime"] ?? bucket["reset_time"]), period: duration))
            }
        }
        if account.windows.isEmpty {
            let cascade = user["cascadeModelConfigData"] as? JSON ?? [:]
            var models = cascade["clientModelConfigs"] as? [JSON] ?? raw["clientModelConfigs"] as? [JSON] ?? []
            if let keyed = raw["models"] as? JSON {
                models += keyed.sorted(by: { $0.key < $1.key }).map { key, raw in
                    var model = raw as? JSON ?? [:]; model["label"] = model["displayName"] ?? key; return model
                }
            }
            for (index, model) in models.enumerated() {
                guard let quota = model["quotaInfo"] as? JSON else { continue }
                account.windows.append(QuotaWindow(id: "ag-model-\(index)", title: string(model["label"] ?? model["displayName"]) ?? "Model \(index + 1)",
                    remaining: number(quota["remainingFraction"]).map { max(0, min(100, $0 * 100)) }, reset: date(quota["resetTime"]), period: nil))
            }
        }
        guard !account.windows.isEmpty else { throw SubscriptionError.message("Antigravity did not return quota data. Reopen Antigravity and check that you are signed in.") }
        account.updatedAt = now
        return account
    }
}
