#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/build/BurndownBar.app"
if [[ ! -x "$APP/Contents/MacOS/BurndownBar" ]]; then
  echo "Build the app first with: bash build.sh" >&2
  exit 1
fi

# Stop the app before clearing preferences so it cannot write them back.
killall BurndownBar 2>/dev/null || true
sleep 1

for domain in local.burndownbar local.easycli.bar; do
  defaults delete "$domain" 2>/dev/null || true
  if defaults read "$domain" >/dev/null 2>&1; then
    echo "Could not clear preferences for $domain. Run this script from your Terminal session." >&2
    exit 1
  fi
done

for service in local.burndownbar easycli.bar.subscriptions; do
  for ((attempt=0; attempt<100; attempt++)); do
    security delete-generic-password -s "$service" >/dev/null 2>&1 || break
  done
  if security find-generic-password -s "$service" >/dev/null 2>&1; then
    echo "Could not clear Keychain credentials for $service." >&2
    exit 1
  fi
done

open -n "$APP" --args --replace-running
echo "Started BurndownBar with fresh app preferences and Keychain credentials."
