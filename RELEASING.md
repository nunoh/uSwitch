# Releasing

Notes for the project maintainer. Not user-facing.

## Cutting a release

Bump `VERSION` in `Makefile` and add a `## YYYY-MM-DD (vX.Y)` block to `CHANGELOG.md`. Then:

```sh
make install                # release build → dist/uSwitch.app + /Applications
ditto -c -k --keepParent dist/uSwitch.app dist/uSwitch-v0.X.zip
git tag v0.X && git push --tags

gh release create v0.X dist/uSwitch-v0.X.zip \
  --title "v0.X" \
  --notes "$(sed -n '/^## .*v0\.X/,/^## /{/^## [^v]/!p;}' CHANGELOG.md | sed '$d')"
```

The `ditto -c -k --keepParent` form preserves the bundle's code signature and symlinks — `zip -r` can mangle `.app` internals.

## Signing

`scripts/setup-cert.sh` creates a self-signed cert (`uSwitch Self-Signed`) in the login keychain on first run. Bundle id (`com.nh.uswitch`) is stable so Accessibility / Screen Recording grants survive rebuilds.

The app is **ad-hoc signed, not notarized.** First-launch users need right-click → Open. README mentions this; revisit if/when notarization is set up.

## Version surfaces

A version bump touches three places:

- `Makefile` — `VERSION ?= 0.X`
- `CHANGELOG.md` — new dated entry; bundled into the .app via the install target
- `Resources/Info.plist` — `__VERSION__` placeholder is filled by `make install`

The About panel reads `CFBundleShortVersionString`, so as long as `make install` runs the value flows through.
