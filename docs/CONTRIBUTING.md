# Contributing

Contributions are welcome — especially new providers, parser edge-case fixes, accessibility improvements, and chart enhancements.

## Development Workflow

1. **Fork & clone** the repository, then run the full build + test suite:
   ```sh
   bash build.sh
   ```
2. In restricted/CI environments without a macOS WindowServer session, skip graphical icon-sizing checks with:
   ```sh
   BURNDOWNBAR_HEADLESS=1 bash build.sh
   ```
3. To regenerate and visually inspect UI previews (dark mode):
   ```sh
   build/BurndownBar.app/Contents/MacOS/BurndownBar --render-previews
   ```
   Previews are written to `build/previews/`.

## Adding a New Provider

1. **Register the origin**: Add a case to `AccountOrigin` in [`Sources/Providers/Shared/ProviderModels.swift`](../Sources/Providers/Shared/ProviderModels.swift) (and `additional`), plus its display name in `Account.providerName(for:)` in [`Sources/Models.swift`](../Sources/Models.swift).
2. **Add brand assets**:
   - Place a `128x128` 8-bit RGBA template `.png` in `Assets/Providers/`, and retain the official source file in `Assets/Providers/originals/`.
   - Register it in [`Sources/Providers/ProviderLogo.swift`](../Sources/Providers/ProviderLogo.swift) and [`Sources/Providers/ProviderTheme.swift`](../Sources/Providers/ProviderTheme.swift).
   - Record the official source URL, local source filename, SHA-256 digest, and trademark attribution in `Assets/Providers/sources.json`.
3. **Allowlist & credentials**:
   - Add the API host to the `allowed` list in [`Sources/Providers/Shared/SubscriptionClient.swift`](../Sources/Providers/Shared/SubscriptionClient.swift) (HTTPS only; `NoRedirectDelegate` blocks credential-leaking redirects).
   - Add any environment variable names to `SubscriptionCredentials.keyVariables` in [`Sources/Providers/Shared/ProviderCredentials.swift`](../Sources/Providers/Shared/ProviderCredentials.swift).
4. **Implement pure parser + client**:
   - Keep JSON parsing pure and deterministic in `Sources/Usage/Providers/<Provider>/` (`AdditionalParsers` or `SubscriptionParser`). Never invent full quotas or `$0` spend when fields are missing — return `nil` or throw a clear `SubscriptionError`.
   - Implement network calls in `Sources/Providers/<Provider>/` and wire routing in [`Sources/Providers/Shared/ProviderRouting.swift`](../Sources/Providers/Shared/ProviderRouting.swift).
5. **Wire UI & connection instructions**:
   - Update `connect(_:)` in [`Sources/Store.swift`](../Sources/Store.swift) and `connectionInstructions` / `signInButtonTitle` in [`Sources/Dashboard.swift`](../Sources/Dashboard.swift).
6. **Add tests**:
   - Add parser unit tests (valid payloads, edge cases, malformed rejection) in `Tests/Providers/AdditionalProviderTests.swift`.
   - Add end-to-end mocked HTTP tests using `FixtureURLProtocol` in [`Tests/TransportTests.swift`](../Tests/TransportTests.swift).

## Engineering & Testing Guidelines

- **No live network or real credentials in tests**: All automated checks in `--self-test` and `--transport-tests` must remain offline and deterministic using synthetic fixtures. Never write test secrets into the user's real macOS Keychain.
- **Validate dynamic path IDs**: Any user- or API-supplied ID interpolated into URL paths must pass `SubscriptionClient.safeID` / `safeSlug` to prevent path traversal.
- **Keep comments & docstrings clean**: Preserve existing comments; document non-obvious invariants (e.g., UTC vs. local day boundaries, inclusive vs. exclusive cached token counts).

## Pull Request Checklist

- [ ] `bash build.sh` passes cleanly (all self-tests, icon tests, and transport tests)
- [ ] New provider hosts are allowlisted in `SubscriptionClient` and path segments are validated
- [ ] New UI changes are verified with `--render-previews`
- [ ] No real tokens, cookies, emails, or local paths are included in fixtures or screenshots
