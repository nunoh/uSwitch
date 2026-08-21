# uSwitch

> HyperSwitch, but µ. A tiny window switcher with live thumbnails for macOS and GNOME.

uSwitch is available as a native Swift app for macOS and a GNOME Shell extension for Linux.

## Features

- **Live thumbnails** of every window on the current Space or workspace.
- **Every window gets its own tile**, including multiple windows from the same app.
- **Fast switching** — a quick key flick switches without flashing the popup.
- **Small and native** — a Swift app on macOS and a GNOME Shell extension on Linux; no Electron.
- **Doesn't leak Escape on macOS** — global Cmd+Esc bindings (iTerm, etc.) keep working.

## Why?

[HyperSwitch](https://bahoom.com/hyperswitch) set the bar for thumbnail-based window switching on macOS, but it is no longer maintained — it nags with a "Check for updates" prompt and crashes intermittently. [AltTab](https://alt-tab.app/) is actively developed and far more configurable, but its key handling can conflict with terminal workflows that bind Cmd+Esc ([lwouis/alt-tab-macos#1217](https://github.com/lwouis/alt-tab-macos/issues/1217)).

uSwitch targets the narrow gap between them: HyperSwitch's switching model in a small, current implementation that leaves the rest of your key bindings alone. The GNOME extension brings the same window-first, thumbnail-based switching model to Linux instead of grouping windows by application.

## Install

### macOS

Grab the latest Apple Silicon `.zip` from [Releases](https://github.com/nunoh/uSwitch/releases), unzip it, and drop `uSwitch.app` into `/Applications`. Or [build from source](#build-from-source).

> macOS 13+. Release builds are ad-hoc signed and not notarized. After the first blocked launch, open **System Settings → Privacy & Security**, scroll to **Security**, click **Open Anyway**, then confirm **Open**. Later launches work normally.

**Managed Mac (corporate MDM):** right-click → Open may be blocked. Instead, copy the `.app` via AirDrop, USB, or any means other than a browser download, then strip the quarantine flag before opening:
```sh
xattr -dr com.apple.quarantine /Applications/uSwitch.app
```
No admin rights needed. Gatekeeper only checks apps that carry the quarantine flag.

### GNOME

The extension supports GNOME Shell 48–50 and has been tested on Ubuntu 26.04 with GNOME Shell 50.1 on Wayland.

Clone the repository, then install and enable the extension:

```sh
git clone https://github.com/nunoh/uSwitch.git
cd uSwitch
make install-gnome-extension
gnome-extensions enable uswitch@nh.com
```

After updating the extension, log out and back in so GNOME Shell loads the new code. Everything is installed for the current user; do not run these commands with `sudo`.

## First run on macOS

uSwitch needs two permissions:

- **Accessibility** — to capture Cmd+Tab before the system does.
- **Screen Recording** — to render window thumbnails.

macOS will prompt on first launch. Grant both in **System Settings → Privacy & Security**, then relaunch.

## Usage

### macOS

| Key | Action |
| --- | --- |
| <kbd>Cmd</kbd>+<kbd>Tab</kbd> | Open switcher / cycle forward |
| <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>Tab</kbd> | Cycle backward |
| Release <kbd>Cmd</kbd> | Raise selected window |
| <kbd>Esc</kbd> | Cancel (swallowed — won't trigger system shortcuts) |

The menu bar icon has **About**, **Launch at Login**, and **Quit**. The About panel links to this repo and shows the changelog.

### GNOME

| Key | Action |
| --- | --- |
| <kbd>Alt</kbd>+<kbd>Tab</kbd> or <kbd>Super</kbd>+<kbd>Tab</kbd> | Open switcher / cycle forward |
| Add <kbd>Shift</kbd> | Cycle backward |
| Release <kbd>Alt</kbd> or <kbd>Super</kbd> | Raise selected window |
| <kbd>Esc</kbd> | Cancel |

The extension replaces GNOME's application and window switchers so that every window appears as a separate tile. Only windows on the current workspace are shown.

## Build from source

### macOS

```sh
make dev      # debug build, signs with the local cert, runs in foreground
make bundle   # release build into dist/uSwitch.app
make release  # release build + versioned Apple Silicon zip
make install  # release build into /Applications and launches
```

Local `dev`, `bundle`, and `install` builds use the stable self-signed certificate from `scripts/setup-cert.sh`, so permission grants persist across local rebuilds. Downloadable release archives use an ad-hoc signature so they do not depend on a certificate that exists only on the build machine.

### GNOME

For GNOME extension development and debugging notes, see [gnome-extension/DEVELOPING.md](gnome-extension/DEVELOPING.md).

## Roadmap

See [PRD.md](PRD.md) for v1 scope. Out of scope for now: cross-Space windows, settings UI, custom hotkeys, per-app cycle.

## About the name

The `u` is `µ` — it's HyperSwitch in a smaller package.

## License

[MIT](LICENSE). Not affiliated with HyperSwitch or Bahoom.
