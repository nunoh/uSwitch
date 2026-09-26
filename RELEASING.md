# Releasing

Notes for the project maintainer. Not user-facing.

## Flow

Releases are automated with [release-please](https://github.com/googleapis/release-please) and GitHub Actions.

1. **Every change lands on `main` through a PR.** Direct pushes are blocked. PRs are squash-merged and the **PR title becomes the commit subject**, so it must be a [Conventional Commit](https://www.conventionalcommits.org/) (`feat: …`, `fix: …`). The `PR title` check enforces this, and `CI` must pass.
2. **release-please keeps a release PR open** (`chore: release vX.Y.Z`). Each merge to `main` updates it: next version, `CHANGELOG.md` entry, `version.txt`.
3. **Merge the release PR to ship.** The `Release` workflow then tags `vX.Y.Z`, creates the GitHub release with the changelog entry as notes, builds `uSwitch-vX.Y.Z-arm64.dmg` and `.zip` on a macOS runner, and attaches both to the release with a `SHA256SUMS.txt` and a build provenance attestation.

Do not edit `CHANGELOG.md` or `version.txt` in feature PRs. release-please owns them.

## Writing PR titles

The PR title is the changelog entry, so write it for users.

| Type | Changelog section | Version bump (pre-1.0) |
|------|-------------------|------------------------|
| `feat` | ✨ Features | minor (0.3.0 → 0.4.0) |
| `perf` | 🔧 Improvements | patch |
| `fix`, `revert` | 🐛 Fixes | patch |
| `refactor`, `docs`, `build`, `ci`, `test`, `style`, `chore` | hidden | none on their own |

A `!` after the type (`feat!: …`) or a `BREAKING CHANGE:` footer marks a breaking change. Before 1.0 that is still a minor bump.

## Editing the release

The release PR is a normal PR on the `release-please--branches--main` branch. To reword the changelog, edit `CHANGELOG.md` on that branch before merging. release-please rewrites the branch when another PR merges to `main`, so edit it last.

To force a version, add `Release-As: 1.0.0` to the body of a commit merged to `main`.

## Homebrew

The cask lives in [nunoh/homebrew-tap](https://github.com/nunoh/homebrew-tap). Its `Update uSwitch` workflow runs hourly, reads the latest release's `SHA256SUMS.txt`, and commits the new version. Run it from that repo's Actions tab to publish at once. Nothing in this repo needs a token for it.

## Rebuilding assets

If the asset build fails after the release exists, run the `Release` workflow manually (Actions → Release → Run workflow) with the tag, e.g. `v0.3.0`. It rebuilds and re-uploads the DMG and zip.

## Verifying a download

```sh
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
gh attestation verify uSwitch-vX.Y.Z-arm64.dmg --repo nunoh/uSwitch
```

The attestation proves the file was built by this repo's `Release` workflow. Release builds are self-signed, not notarized, so this is the most reliable way to tell an official build from a rebuilt copy.

## Local builds

```sh
make dmg                  # → dist/uSwitch-vX.Y.Z-arm64.dmg (+ .zip), version from version.txt
make dmg VERSION=0.3.0    # override the version
```

The `release` target uses `ditto -c -k --keepParent`, which preserves the bundle's code signature and symlinks. `zip -r` can mangle `.app` internals. The DMG holds `uSwitch.app` and an `Applications` link for drag-to-install.

## Tokens

release-please runs with `RELEASE_PLEASE_TOKEN` when that secret exists, else the default `GITHUB_TOKEN`. PRs opened with `GITHUB_TOKEN` do not trigger other workflows, so the release PR has no CI run and the admin merges it by bypassing the required checks. A fine-grained PAT with *Contents* and *Pull requests* read/write on this repo, stored as `RELEASE_PLEASE_TOKEN`, makes CI run on the release PR.

## Signing

`scripts/setup-cert.sh` creates a self-signed cert (`uSwitch Self-Signed`, SHA-1 `BC502E94…3A39`) in the login keychain on first run. Every build is signed with it: local `dev`, `bundle`, `install`, and the CI release. macOS ties Accessibility / Screen Recording grants to the signing certificate, so they survive rebuilds and updates. An ad-hoc signature would tie them to the build's hash and reset them on every update.

CI imports the cert from two secrets and fails the release if the app is not signed with it:

| Secret | Value |
|--------|-------|
| `MACOS_SIGN_P12` | The cert and private key as a base64 `.p12` |
| `MACOS_SIGN_P12_PASSWORD` | The `.p12` password |

To set them: Keychain Access → login → My Certificates → right-click **uSwitch Self-Signed** → Export… → `uswitch-sign.p12` with a password. Then:

```sh
base64 -i uswitch-sign.p12 | gh secret set MACOS_SIGN_P12
gh secret set MACOS_SIGN_P12_PASSWORD
rm uswitch-sign.p12
```

Keep the cert: a new one changes the signing identity, and every user must grant the permissions again. If you lose it, run `make reset-perms` locally after installing the first build with the new one, and update `SIGN_CERT_SHA1` in `release.yml`.

The release is **not notarized**. The Homebrew cask removes the quarantine flag after install, so brew users skip Gatekeeper. Users who download the DMG approve it once in System Settings → Privacy & Security → Open Anyway. Revisit when a Developer ID is available.

## Version surfaces

- `version.txt` — bumped by release-please; the Makefile reads it as the default `VERSION`
- `CHANGELOG.md` — written by release-please; bundled into the app and shown in About → Changelog
- `Resources/Info.plist` — `__VERSION__` placeholder is filled by `make bundle`, `make release`, `make dmg`, or `make install`

The About panel reads `CFBundleShortVersionString`, so the version flows through every release build.
