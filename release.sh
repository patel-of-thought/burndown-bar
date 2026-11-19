#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

usage() {
  cat <<'EOF'
Usage: RELEASE_SIGN_IDENTITY='Developer ID Application: ...' NOTARY_PROFILE=profile bash release.sh

Builds and tests a clean Git checkout, signs with hardened runtime,
notarizes and staples the app, then writes a versioned ZIP and SHA-256
checksum to dist/. Store notarization credentials first with:
  xcrun notarytool store-credentials profile
EOF
}
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then usage; exit 0; fi
if [[ $# -ne 0 ]]; then usage >&2; exit 2; fi

identity="${RELEASE_SIGN_IDENTITY:-}"
profile="${NOTARY_PROFILE:-}"
if [[ -z "$identity" || -z "$profile" ]]; then
  echo "Set RELEASE_SIGN_IDENTITY and NOTARY_PROFILE before releasing." >&2
  exit 1
fi
if [[ ! "$identity" == "Developer ID Application:"* ]]; then
  echo "RELEASE_SIGN_IDENTITY must name a Developer ID Application certificate." >&2
  exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "Commit or remove all working-tree changes before releasing." >&2
  exit 1
fi
if ! security find-identity -v -p codesigning | grep -Fq "$identity"; then
  echo "The requested Developer ID Application identity is not available in Keychain." >&2
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ || ! "$build_number" =~ ^[0-9]+$ ]]; then
  echo "Info.plist needs a semantic version (optionally prerelease) and numeric build number." >&2
  exit 1
fi
artifact="dist/BurndownBar-${version}+${build_number}.zip"
if [[ -e "$artifact" || -e "$artifact.sha256" ]]; then
  echo "Release artifact already exists: $artifact" >&2
  exit 1
fi

BURNDOWNBAR_DEV_MODE=0 BURNDOWNBAR_HEADLESS=1 bash build.sh

staging=$(mktemp -d "$PWD/build/.release.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/BurndownBar.app"
ditto build/BurndownBar.app "$app"
codesign --force --sign "$identity" --options runtime --timestamp "$app"
codesign --verify --deep --strict --verbose=2 "$app"

submission="$staging/BurndownBar-notary.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$submission"
xcrun notarytool submit "$submission" --keychain-profile "$profile" --wait --output-format json > "$staging/notary-result.json"
python3 -c 'import json,sys; result=json.load(open(sys.argv[1])); status=result.get("status"); print("Notarization:", status); sys.exit(0 if status == "Accepted" else 1)' "$staging/notary-result.json"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$app" "$artifact"
shasum -a 256 "$artifact" > "$artifact.sha256"
echo "Created $artifact and $artifact.sha256"
