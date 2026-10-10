#!/bin/bash
# CI only: sign the zip for release TAG with SPARKLE_ED_KEY and write a
# one-item dist/appcast.xml that points at that release's download URL.
set -euo pipefail

zip="$1"
tag="$2"

if [ -z "${SPARKLE_ED_KEY:-}" ]; then
  echo "::error::SPARKLE_ED_KEY is not set; see RELEASING.md#sparkle-update-signing"
  exit 1
fi
rm -rf dist/appcast-input
mkdir -p dist/appcast-input
cp "$zip" dist/appcast-input/
printf '%s' "$SPARKLE_ED_KEY" | .build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --ed-key-file - \
  --download-url-prefix "https://github.com/nunoh/uSwitch/releases/download/${tag}/" \
  dist/appcast-input
cp dist/appcast-input/appcast.xml dist/appcast.xml
