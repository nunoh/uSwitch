# Releasing

Notes for the project maintainer. Not user-facing.

## Cutting a release

Bump `VERSION` in `Makefile` and add a `## YYYY-MM-DD (vX.Y)` block to `CHANGELOG.md`. Then:

```sh
make release VERSION=0.X    # → dist/uSwitch-v0.X-arm64.zip
git tag v0.X && git push --tags

gh release create v0.X dist/uSwitch-v0.X-arm64.zip \
  --title "v0.X" \
  --notes "$(sed -n '/^## .*v0\.X/,/^## /{/^## [^v]/!p;}' CHANGELOG.md | sed '$d')"
```

The `release` target uses `ditto -c -k --keepParent`, which preserves the bundle's code signature and symlinks. `zip -r` can mangle `.app` internals.

## Signing

`scripts/setup-cert.sh` creates a self-signed cert (`uSwitch Self-Signed`) in the login keychain on first run. Local `dev`, `bundle`, and `install` builds use it so Accessibility / Screen Recording grants survive rebuilds.

The downloadable release is **ad-hoc signed, not notarized**. First-launch users need to approve it in System Settings → Privacy & Security → Open Anyway. README mentions this; revisit if/when notarization is set up.

## Version surfaces

A version bump touches three places:

- `Makefile` — `VERSION ?= 0.X`
- `CHANGELOG.md` — new dated entry; bundled into the app by every release build
- `Resources/Info.plist` — `__VERSION__` placeholder is filled by `make bundle`, `make release`, or `make install`

The About panel reads `CFBundleShortVersionString`, so the version flows through every release build.
