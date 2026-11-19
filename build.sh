#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/BurndownBar.app"
DEV_MODE="${BURNDOWNBAR_DEV_MODE:-$(defaults read local.burndownbar developerMode 2>/dev/null || true)}"
mkdir -p build
BUILD_ROOT="$(mktemp -d "$PWD/build/.build.XXXXXX")"
STAGING_ROOT=""
BUILD_APP="$APP"
trap 'rm -rf "$BUILD_ROOT"' EXIT
if [[ "$DEV_MODE" == "1" ]]; then
  STAGING_ROOT="$BUILD_ROOT/staged"
  BUILD_APP="$STAGING_ROOT/BurndownBar.app"
fi
mkdir -p "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources" build/module-cache
mkdir -p "$BUILD_ROOT/source"
cp -R Sources Tests "$BUILD_ROOT/source/"
sources=()
while IFS= read -r -d '' source; do
  sources+=("$source")
done < <(find "$BUILD_ROOT/source/Sources" "$BUILD_ROOT/source/Tests" -type f -name '*.swift' -print0)
xcrun swiftc -swift-version 5 -parse-as-library -O \
  -module-cache-path "$PWD/build/module-cache" \
  -framework AppKit -framework SwiftUI -framework Charts -framework Security -framework LocalAuthentication -lsqlite3 \
  "${sources[@]}" -o "$BUILD_APP/Contents/MacOS/BurndownBar"
cp Info.plist "$BUILD_APP/Contents/Info.plist"
cp LICENSE "$BUILD_APP/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$BUILD_APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp Assets/AppIcon.icns "$BUILD_APP/Contents/Resources/AppIcon.icns"
mkdir -p "$BUILD_APP/Contents/Resources/ProviderIcons"
cp Assets/Providers/*.png Assets/Providers/sources.json "$BUILD_APP/Contents/Resources/ProviderIcons/"
codesign --force --sign - "$BUILD_APP"
test_args=(--self-test)
if [[ "${BURNDOWNBAR_HEADLESS:-0}" == "1" ]]; then test_args+=(--headless); fi
"$BUILD_APP/Contents/MacOS/BurndownBar" "${test_args[@]}"
"$BUILD_APP/Contents/MacOS/BurndownBar" --transport-tests
if [[ -n "$STAGING_ROOT" ]]; then
  BACKUP_APP="$STAGING_ROOT/previous.app"
  if [[ -d "$APP" ]]; then mv "$APP" "$BACKUP_APP"; fi
  if ! mv "$BUILD_APP" "$APP"; then
    if [[ -d "$BACKUP_APP" ]]; then mv "$BACKUP_APP" "$APP"; fi
    exit 1
  fi
fi
printf 'Built %s\n' "$APP"
