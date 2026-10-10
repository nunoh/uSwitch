#!/bin/bash
# CI only: import the "uSwitch Self-Signed" certificate from the
# MACOS_SIGN_P12 / MACOS_SIGN_P12_PASSWORD secrets into a temp keychain.
set -euo pipefail

if [ -z "${MACOS_SIGN_P12:-}" ]; then
  echo "::error::MACOS_SIGN_P12 is not set; see RELEASING.md#signing"
  exit 1
fi
kc="$RUNNER_TEMP/signing.keychain-db"
kc_password=$(openssl rand -hex 16)
security create-keychain -p "$kc_password" "$kc"
security set-keychain-settings -lut 21600 "$kc"
security unlock-keychain -p "$kc_password" "$kc"
echo "$MACOS_SIGN_P12" | base64 --decode > "$RUNNER_TEMP/sign.p12"
security import "$RUNNER_TEMP/sign.p12" -k "$kc" -P "$MACOS_SIGN_P12_PASSWORD" -T /usr/bin/codesign
rm "$RUNNER_TEMP/sign.p12"
security set-key-partition-list -S apple-tool:,apple: -s -k "$kc_password" "$kc" >/dev/null
security list-keychains -d user -s "$kc" $(security list-keychains -d user | tr -d '"')
