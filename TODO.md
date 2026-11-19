# Release to-do list

The app builds on macOS with `BURNDOWNBAR_HEADLESS=1 bash build.sh`. On 19 November 2026, that command passed 183 self checks and 37 isolated transport checks. The build is locally ad hoc signed; it is not yet a distributable release.

## Before the first public release

- [x] **Publish the source repository.** The initial source and assets are committed to `main` and published to the intended GitHub remote. `build/`, `dist/`, `.DS_Store`, and `launch-video/` are ignored.
- [x] **Add the project's license.** BurndownBar's code and original assets use MIT; provider icon attribution remains in `THIRD_PARTY_NOTICES.md`. The recorded SVG Git blob IDs were checked against all 11 local SVG files.
- [x] **Complete the asset rights audit.** The creator confirmed `AppIcon`, the README screenshots, and the OpenRouter SVG are original BurndownBar artwork. The OpenRouter icon is recorded in `Assets/Providers/sources.json`; provider marks remain their owners' trademarks.
- [x] **Set the app identity.** Keep `local.burndownbar` as the bundle identifier and Keychain service for the first release, preserving existing preferences and credentials.
- [x] **Set the release version.** `Info.plist` is `1.0.0` with build number `6`; the dashboard reads the version from the bundle.
- [ ] **Validate the distribution build.** `release.sh` now builds from a clean checkout, runs the offline checks, signs with a Developer ID Application certificate and hardened runtime, verifies the signature, notarizes, staples, checks Gatekeeper, and creates a versioned ZIP with a SHA-256 checksum. A Developer ID certificate and notarization profile are required to run it end to end; signing access is not currently available. Do not publish the ad hoc signed `build/BurndownBar.app`.
- [ ] **Write install and update instructions for users.** Replace the README's `git clone <your-repo-url>` placeholder once the remote is known. Document downloading, verifying, installing, updating, and removing the release build. Keep the destructive `clean-install.command` clearly identified as a developer reset, since it deletes preferences and Keychain entries.
- [ ] **Publish a privacy and credential disclosure.** Explain the Keychain entries, browser cookie import, local CLI/config file reads, outbound provider requests, and any local caching. Verify the claims against the code and add a user-facing privacy document linked from the README.
- [ ] **Validate a clean-user install.** Test the signed and notarized artifact on a supported macOS 14+ machine with no prior BurndownBar state. Check first launch, icon, menu bar, preferences, provider connection, Keychain prompts, quit/relaunch, and updating from an older build. Also test a current macOS version.
- [ ] **Prepare the release record.** Add a changelog or release notes, tag the exact source revision, publish the artifact and checksum, and verify a fresh download matches the checksum and passes Gatekeeper assessment.

## Release automation and follow-up

- [ ] Run the headless build and offline test suites on a macOS CI runner for each pull request and release tag. Keep signing and notarization secrets restricted to the release workflow.
- [ ] Run `--render-previews` in a graphical macOS session and inspect all supported views at light/dark appearance and increased text size. The headless build skips native provider icon sizing checks.
- [ ] Add a lightweight manual compatibility check for provider APIs before each release; mocked transport fixtures cannot detect upstream API changes.
- [ ] Decide how users will report bugs and receive update notices, and link those channels from the README.
- [ ] **Publish the website and its images to Cloudflare.** Log in with `npx wrangler login`, then run `site/publish.sh` to deploy `site/` as the `burndownbar` Workers static-assets site. Confirm the app icon, the four screenshots in `site/images/screenshots/`, and the provider logos in `site/images/providers/` load from the deployed URL, and that `wrangler.jsonc`, `publish.sh`, and `.assetsignore` are not served.
