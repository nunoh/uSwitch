#!/bin/bash
# CI only: sign the zip for release TAG with SPARKLE_ED_KEY and write a
# one-item dist/appcast.xml that points at that release's download URL.
# An optional Markdown NOTES file is embedded as the update's release notes,
# which Sparkle shows in its update window.
set -euo pipefail

zip="$1"
tag="$2"
notes="${3:-}"

if [ -z "${SPARKLE_ED_KEY:-}" ]; then
  echo "::error::SPARKLE_ED_KEY is not set; see RELEASING.md#sparkle-update-signing"
  exit 1
fi
rm -rf dist/appcast-input
mkdir -p dist/appcast-input
cp "$zip" dist/appcast-input/
# generate_appcast picks up notes that share the archive's base name.
if [ -n "$notes" ] && [ -s "$notes" ]; then
  base=$(basename "$zip" .zip)
  cp "$notes" "dist/appcast-input/${base}.md"
fi
printf '%s' "$SPARKLE_ED_KEY" | .build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --ed-key-file - \
  --embed-release-notes \
  --download-url-prefix "https://github.com/nunoh/uSwitch/releases/download/${tag}/" \
  dist/appcast-input
cp dist/appcast-input/appcast.xml dist/appcast.xml
