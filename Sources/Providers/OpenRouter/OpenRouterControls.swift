import Foundation

extension SubscriptionClient {
    /// Updates an OpenRouter API key's disabled state or spending limit (`PATCH /api/v1/keys/{hash}`).
    func updateOpenRouterKey(hash: String, disabled: Bool? = nil, limitUSD: Double? = nil, clearLimit: Bool = false, limitReset: String? = nil, apiKey suppliedKey: String? = nil) async throws {
        guard Self.safeID(hash) else { throw SubscriptionError.message("Invalid OpenRouter key identifier.") }
        guard let apiKey = suppliedKey ?? SubscriptionCredentials.namedKey(account: "openrouter-key", variable: "OPENROUTER_MANAGEMENT_KEY") else {
            throw SubscriptionError.message("OpenRouter Management Key is required to modify keys.")
        }
        var body: JSON = [:]
        if let disabled { body["disabled"] = disabled }
        if clearLimit { body["limit"] = NSNull() }
        else if let limitUSD { body["limit"] = limitUSD }
        if let limitReset { body["limit_reset"] = limitReset.isEmpty ? NSNull() : limitReset }
        guard !body.isEmpty else { return }

        let result = try await requestStatus(
            url: "https://openrouter.ai/api/v1/keys/\(hash)",
            provider: "OpenRouter",
            method: "PATCH",
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: body
        )
        if result.status == 401 || result.status == 403 { throw SubscriptionError.unauthorized("OpenRouter") }
        guard (200...299).contains(result.status) else { throw SubscriptionError.http(result.status) }
    }

    /// Toggles Zero Data Retention (ZDR) on an existing guardrail, or creates a BurndownBar ZDR guardrail and binds active keys.
    func setOpenRouterZDR(enabled: Bool, guardrailID: String?, keyHashes: [String], apiKey suppliedKey: String? = nil) async throws {
        guard let apiKey = suppliedKey ?? SubscriptionCredentials.namedKey(account: "openrouter-key", variable: "OPENROUTER_MANAGEMENT_KEY") else {
            throw SubscriptionError.message("OpenRouter Management Key is required to update guardrails.")
        }
        let validHashes = keyHashes.filter(Self.safeID(_:))
        if enabled && validHashes.isEmpty {
            throw SubscriptionError.message("No active OpenRouter keys are available. Refresh keys before enabling ZDR.")
        }
        let headers = ["Authorization": "Bearer \(apiKey)"]
        let targetID: String
        if let guardrailID, Self.safeID(guardrailID) {
            targetID = guardrailID
        } else {
            let created = try await requestStatus(
                url: "https://openrouter.ai/api/v1/guardrails",
                provider: "OpenRouter",
                method: "POST",
                headers: headers,
                body: ["name": "BurndownBar ZDR", "enforce_zdr": false]
            )
            if created.status == 401 || created.status == 403 { throw SubscriptionError.unauthorized("OpenRouter") }
            guard (200...299).contains(created.status),
                  let json = created.value as? JSON,
                  let newID = string((json["data"] as? JSON)?["id"] ?? json["id"]),
                  Self.safeID(newID) else {
                throw SubscriptionError.http(created.status)
            }
            targetID = newID
        }

        if enabled {
            let assignment: (status: Int, value: Any)
            do {
                assignment = try await requestStatus(
                    url: "https://openrouter.ai/api/v1/guardrails/\(targetID)/keys/bulk-assign",
                    provider: "OpenRouter",
                    method: "POST",
                    headers: headers,
                    body: ["key_hashes": validHashes]
                )
            } catch {
                throw SubscriptionError.message("Active keys could not be attached to the ZDR guardrail. Check OpenRouter before relying on ZDR.")
            }
            guard (200...299).contains(assignment.status) else {
                throw SubscriptionError.message("OpenRouter rejected the active key assignment (HTTP \(assignment.status)). Check OpenRouter before relying on ZDR.")
            }
        }

        let result = try await requestStatus(
            url: "https://openrouter.ai/api/v1/guardrails/\(targetID)",
            provider: "OpenRouter",
            method: "PATCH",
            headers: headers,
            body: ["enforce_zdr": enabled]
        )
        if result.status == 401 || result.status == 403 { throw SubscriptionError.unauthorized("OpenRouter") }
        guard (200...299).contains(result.status) else { throw SubscriptionError.http(result.status) }
    }
}
