# uSwitch

> HyperSwitch, but µ. A tiny native Cmd+Tab replacement for macOS with live window thumbnails.

## Features

- **Live thumbnails** of every window on the current Space.
- **Doesn't leak Escape** — global Cmd+Esc bindings (iTerm, etc.) keep working.
- **Native Swift**, no Electron, no daemons. ~1k LOC.
- **Stays out of your way** — menu bar only, no Dock icon.

## Why?

I used [HyperSwitch](https://bahoom.com/hyperswitch) for years and loved it, but it's now unmaintained — kept nagging me with a "Check for updates" popup and would randomly crash. [AltTab](https://alt-tab.app/) didn't play nicely with my iTerm2 workflow ([lwouis/alt-tab-macos#1217](https://github.com/lwouis/alt-tab-macos/issues/1217)). So I vibecoded my own.

## Install

Grab the latest `.app` from [Releases](https://github.com/nunoh/uSwitch/releases) and drop it into `/Applications`. Or [build from source](#build-from-source).

> macOS 13+. The app is ad-hoc signed; on first launch right-click → Open to bypass Gatekeeper.

## First run

uSwitch needs two permissions:

- **Accessibility** — to capture Cmd+Tab before the system does.
- **Screen Recording** — to render window thumbnails.

macOS will prompt on first launch. Grant both in **System Settings → Privacy & Security**, then relaunch.

## Usage

| Key | Action |
| --- | --- |
| <kbd>Cmd</kbd>+<kbd>Tab</kbd> | Open switcher / cycle forward |
| <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>Tab</kbd> | Cycle backward |
| Release <kbd>Cmd</kbd> | Raise selected window |
| <kbd>Esc</kbd> | Cancel (swallowed — won't trigger system shortcuts) |

The menu bar icon has **About**, **Launch at Login**, and **Quit**. The About panel links to this repo and shows the changelog.

## Build from source

```sh
make dev      # debug build, signs ad-hoc, runs in foreground
make install  # release build into /Applications and launches
```

Both targets handle the self-signed cert via `scripts/setup-cert.sh`. Bundle id is stable (`com.nh.uswitch`) so permission grants persist across rebuilds.

## Roadmap

See [PRD.md](PRD.md) for v1 scope. Out of scope for now: cross-Space windows, settings UI, custom hotkeys, per-app cycle.

## About the name

The `u` is `µ` — it's HyperSwitch in a smaller package.
