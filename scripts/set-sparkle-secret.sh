#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
umask 077
key_dir="$(mktemp -d)"
key_file="$key_dir/private-key"
trap 'rm -rf "$key_dir"' EXIT

.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.nh.uswitch -x "$key_file"
gh secret set SPARKLE_ED_KEY --repo nunoh/uSwitch < "$key_file"
echo "Sparkle release signing key saved as SPARKLE_ED_KEY."
