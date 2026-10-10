#!/bin/bash
# Markdown release notes for the Sparkle update window and the GitHub release.
#   release-notes.sh unreleased  → feat/fix/perf commits since the last stable tag
#   release-notes.sh vX.Y.Z      → that version's CHANGELOG.md entry
set -euo pipefail

ref="${1:?usage: release-notes.sh unreleased|vX.Y.Z}"

# Drop the PR and commit links release-please appends to each entry.
strip_links() {
  sed -E -e 's/ \(\[#[0-9]+\]\([^)]*\)\)//g' -e 's/ \(\[[0-9a-f]{7,}\]\([^)]*\)\)//g'
}

if [ "$ref" != unreleased ]; then
  version="${ref#v}"
  awk -v v="$version" '
    /^## / {
      if (found) exit
      if (index($0, "[" v "]")) { found = 1; next }
    }
    found { print }
  ' CHANGELOG.md | strip_links | sed -e '/./,$!d'
  exit 0
fi

last=$(git describe --tags --abbrev=0 --match 'v*')

# One changelog section per type, matching release-please's sections.
section() {
  local title="$1" types="$2" lines
  lines=$(git log --no-merges --format='%s' "$last..HEAD" |
    sed -nE "s/^(${types})(\([^)]*\))?!?: (.*)$/* \3/p" |
    sed -E 's/ \(#[0-9]+\)$//')
  if [ -n "$lines" ]; then
    printf '### %s\n\n%s\n\n' "$title" "$lines"
  fi
}

section "✨ Features" "feat"
section "🔧 Improvements" "perf"
section "🐛 Fixes" "fix|revert"
