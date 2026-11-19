import Foundation

extension SubscriptionCredentials {
    struct CodexSession { let token: String; let accountID: String?; let email: String?; let source: String }
    /// Direct Codex sign-in: a token saved here, then `CODEX_ACCESS_TOKEN` env var, then the Codex CLI's own `~/.codex/auth.json` (read only).
    static func codex(authFile: URL = home.appendingPathComponent(".codex/auth.json"),
                      keychain: (String) -> String? = { saved($0) },
                      environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CodexSession {
        var token: String?, accountID: String?, idToken: String?, source = ""
        if let saved = keychain("codex-key") { token = saved; source = "Access token · Keychain" }
        else if let value = environment["CODEX_ACCESS_TOKEN"], !value.isEmpty {
            token = value; source = "Access token · environment"
            if let acct = environment["CODEX_ACCOUNT_ID"], !acct.isEmpty { accountID = acct }
        } else if let data = try? Data(contentsOf: authFile),
                  let root = try? JSONSerialization.jsonObject(with: data) as? JSON, let tokens = root["tokens"] as? JSON,
                  let value = string(tokens["access_token"]) {
            token = value; source = "Codex CLI sign-in"
            accountID = string(tokens["account_id"]); idToken = string(tokens["id_token"])
        }
        guard let token else {
            throw SubscriptionError.message("Sign in with the Codex CLI (codex login) or paste an access token in Connections.")
        }
        let claims = jwt(token)
        if let expiry = date(claims?["exp"]), expiry < Date() {
            throw SubscriptionError.message("The Codex sign-in has expired. Open the Codex CLI once to refresh it, then refresh here.")
        }
        let auth = claims?["https://api.openai.com/auth"] as? JSON
        let profile = (claims?["https://api.openai.com/profile"] as? JSON) ?? (idToken.flatMap(jwt)?["https://api.openai.com/profile"] as? JSON)
        let email = string(claims?["email"]) ?? string(profile?["email"]) ?? idToken.flatMap(jwt).flatMap { string($0["email"]) }
        return CodexSession(token: token, accountID: accountID ?? string(auth?["chatgpt_account_id"]) ?? idToken.flatMap(jwt).flatMap { string(($0["https://api.openai.com/auth"] as? JSON)?["chatgpt_account_id"]) },
                            email: email, source: source)
    }
}
