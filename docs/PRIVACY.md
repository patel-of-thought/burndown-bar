# BurndownBar privacy and credentials

This document describes how the current BurndownBar macOS app handles account data. BurndownBar runs on your Mac and connects to the services you enable. It does not require a BurndownBar account.

## Data read on your Mac

- Credentials entered in Connections, including API keys and pasted cookie headers, are saved in macOS Keychain under the `local.burndownbar` service. Saved credentials take priority over supported environment variables. The GitHub Copilot device sign-in token and the optional Artificial Analysis API key are also saved there.
- The app can read existing local credentials when the relevant provider is enabled: Codex's `~/.codex/auth.json`, Factory's `~/.factory/.env`, Cursor desktop sign-in data, and CLIProxyAPI's configuration. It reads the Antigravity desktop app's local service when that provider is enabled. The app also reads CLIProxyAPI's local usage databases for token charts when those databases are present, even if CLIProxyAPI is not selected as a quota source.
- Cursor's default-browser option reads only the Cursor session cookie from the selected browser profile. macOS may ask for access to the browser's Keychain encryption key. BurndownBar keeps the decrypted cookie in memory for requests and does not save it in BurndownBar's Keychain. The manual cookie option does save the cookie in BurndownBar's Keychain.
- The CLIProxyAPI usage reader makes temporary copies of its SQLite databases and write-ahead logs to query them, then removes those copies after each query. It does not edit the original databases.

## Data sent over the network

When a provider is enabled, the app periodically sends its credential or session cookie to that provider's service to fetch account status, quotas, usage, or pricing. The default refresh interval is two minutes and can be changed in Preferences. The app also calls the providers' status services where available. Codex, Grok, and Claude can instead be queried through your local CLIProxyAPI service when you choose that quota source. CLIProxyAPI then makes the provider request using the account signed in there.

An OpenRouter Management Key allows the app to read account analytics and, when you confirm an action, change OpenRouter key limits, paused state, or Zero Data Retention guardrails. An OpenRouter Standard API Key can fetch global rankings. An Artificial Analysis API key fetches model leaderboard data; the app can also read its public leaderboard page. Rankings and pricing responses are cached in memory to limit repeat requests.

**Model Advisor:** If an OpenRouter Standard API Key is available, the default “Get advice when opening tab” setting sends a request when you open Model Advisor. The request includes your selected or typed task, active provider names, aggregated token use, spend, remaining credits and quota where available, top used model names and totals, candidate models and prices, and your advisor settings. It is sent to OpenRouter's Decisions API for the selected decision model. This request can incur OpenRouter charges and is subject to OpenRouter and the selected model provider's data handling rules. Turn off “Get advice when opening tab” in Model Advisor settings to require the **Get Advice** button for each request.

BurndownBar does not include an app-operated telemetry or analytics service in the current source. Provider requests, including Model Advisor requests, are handled by those third parties under their own policies.

## Data kept by BurndownBar

The app stores provider choices, refresh interval, privacy display preference, OpenCode workspace ID, selected dashboard section, and Model Advisor settings in macOS preferences for `local.burndownbar`. Account responses and usage snapshots are held in memory while the app runs. Network clients use ephemeral sessions without a URL cache or automatic cookie storage.

“Hide account emails” masks most of the part before `@` in the app's display; the first character and domain remain visible. It does not stop provider requests or remove account data from memory.

To remove BurndownBar's saved credentials and preferences, quit the app, delete its `local.burndownbar` Keychain entries in Keychain Access, and remove its `local.burndownbar` preferences. Removing the app alone does not necessarily remove those entries. This does not sign you out of provider apps, browsers, or CLI tools.

For privacy questions or bugs, use the [BurndownBar issue tracker](https://github.com/patel-of-thought/burndown-bar/issues).
