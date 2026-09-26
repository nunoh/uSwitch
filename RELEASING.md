# Releasing

Notes for the project maintainer. Not user-facing.

## Flow

Releases are automated with [release-please](https://github.com/googleapis/release-please) and GitHub Actions.

1. **Every change lands on `main` through a PR.** Direct pushes are blocked. PRs are squash-merged and the **PR title becomes the commit subject**, so it must be a [Conventional Commit](https://www.conventionalcommits.org/) (`feat: …`, `fix: …`). The `PR title` check enforces this, and `CI` must pass.
2. **release-please keeps a release PR open** (`chore(main): release X.Y.Z`). Each merge to `main` updates it: next version, `CHANGELOG.md` entry, `version.txt`.
3. **Merge the release PR to ship.** The `Release` workflow then tags `vX.Y.Z`, creates the GitHub release with the changelog entry as notes, builds `uSwitch-vX.Y.Z-arm64.dmg` and `.zip` on a macOS runner, and attaches both to the release.

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

## Rebuilding assets

If the asset build fails after the release exists, run the `Release` workflow manually (Actions → Release → Run workflow) with the tag, e.g. `v0.3.0`. It rebuilds and re-uploads the DMG and zip.

## Local builds

```sh
make dmg                  # → dist/uSwitch-vX.Y.Z-arm64.dmg (+ .zip), version from version.txt
make dmg VERSION=0.3.0    # override the version
```

The `release` target uses `ditto -c -k --keepParent`, which preserves the bundle's code signature and symlinks. `zip -r` can mangle `.app` internals. The DMG holds `uSwitch.app` and an `Applications` link for drag-to-install.

## Tokens

release-please runs with `RELEASE_PLEASE_TOKEN` when that secret exists, else the default `GITHUB_TOKEN`. PRs opened with `GITHUB_TOKEN` do not trigger other workflows, so the release PR has no CI run and the admin merges it by bypassing the required checks. A fine-grained PAT with *Contents* and *Pull requests* read/write on this repo, stored as `RELEASE_PLEASE_TOKEN`, makes CI run on the release PR.

## Signing

`scripts/setup-cert.sh` creates a self-signed cert (`uSwitch Self-Signed`) in the login keychain on first run. Local `dev`, `bundle`, and `install` builds use it so Accessibility / Screen Recording grants survive rebuilds.

The downloadable release is **ad-hoc signed, not notarized**. First-launch users need to approve it in System Settings → Privacy & Security → Open Anyway. README mentions this; revisit if/when notarization is set up.

## Version surfaces

- `version.txt` — bumped by release-please; the Makefile reads it as the default `VERSION`
- `CHANGELOG.md` — written by release-please; bundled into the app and shown in About → Changelog
- `Resources/Info.plist` — `__VERSION__` placeholder is filled by `make bundle`, `make release`, `make dmg`, or `make install`

The About panel reads `CFBundleShortVersionString`, so the version flows through every release build.
