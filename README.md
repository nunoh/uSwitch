# uSwitch

> HyperSwitch, but µ. A tiny window switcher with live thumbnails for macOS and GNOME.

uSwitch is available as a native Swift app for macOS and a GNOME Shell extension for Linux.

## Features

- **Live thumbnails** of every window on the current Space or workspace.
- **Every window gets its own tile**, including multiple windows from the same app.
- **Minimized windows stay visible** — a compact icon + title strip under the active tiles; shown but skipped by the Tab cycle.
- **All-Spaces overview** — <kbd>Option</kbd>+<kbd>Tab</kbd> groups every window by Space (using WindowServer's per-Space lists, so no leftovers), with the current Space marked.
- **Fast switching** — a quick key flick can switch without flashing the popup (optional flick delay, off by default).
- **Small and native** — a Swift app on macOS and a GNOME Shell extension on Linux; no Electron.
- **Doesn't leak Escape on macOS** — global Cmd+Esc bindings (iTerm, etc.) keep working.

## Why?

[HyperSwitch](https://bahoom.com/hyperswitch) set the bar for thumbnail-based window switching on macOS, but it is no longer maintained — it nags with a "Check for updates" prompt and crashes intermittently. [AltTab](https://alt-tab.app/) is actively developed and far more configurable, but its key handling can conflict with terminal workflows that bind Cmd+Esc ([lwouis/alt-tab-macos#1217](https://github.com/lwouis/alt-tab-macos/issues/1217)).

uSwitch targets the narrow gap between them: HyperSwitch's switching model in a small, current implementation that leaves the rest of your key bindings alone. The GNOME extension brings the same window-first, thumbnail-based switching model to Linux instead of grouping windows by application.

## Install

### macOS

Grab the latest Apple Silicon `.dmg` from [Releases](https://github.com/nunoh/uSwitch/releases), open it, and drag `uSwitch.app` into `/Applications`. A `.zip` is attached too. Or [build from source](#build-from-source).

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
| <kbd>Cmd</kbd>+<kbd>Tab</kbd> | Open switcher (current Space) / cycle forward |
| <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>Tab</kbd> | Cycle backward |
| <kbd>Option</kbd>+<kbd>Tab</kbd> | Open all-Spaces overview / cycle forward |
| <kbd>Option</kbd>+<kbd>Shift</kbd>+<kbd>Tab</kbd> | Overview, cycle backward |
| Release <kbd>Cmd</kbd> or <kbd>Option</kbd> | Raise selected window |
| <kbd>Esc</kbd> | Cancel (swallowed — won't trigger system shortcuts) |
| <kbd>Cmd</kbd>+<kbd>Q</kbd> (while open) | Quit the selected app, stay in the switcher |
| <kbd>Cmd</kbd>+<kbd>W</kbd> (while open) | Close the selected window, stay in the switcher |
| <kbd>Cmd</kbd>+<kbd>M</kbd> (while open) | Minimize the selected window, stay in the switcher |
| <kbd>S</kbd> or <kbd>Cmd</kbd>+<kbd>F</kbd> (while open) | Toggle the all-Spaces overview on/off |
| <kbd>Cmd</kbd>+<kbd>,</kbd> (while open) | Open Settings |

The menu bar icon has **Settings…**, **Launch at Login**, **About**, and **Check for Updates…** (plus **Quit**). Settings covers the two shortcuts, minimized-window behaviour, thumbnail size, overview scaling, the flick delay, and the daily update check; it persists in UserDefaults and applies live.

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
make dmg      # release build + versioned Apple Silicon zip and dmg
make install  # release build into /Applications and launches
```

Local `dev`, `bundle`, and `install` builds use the stable self-signed certificate from `scripts/setup-cert.sh`, so permission grants persist across local rebuilds. Downloadable release archives use an ad-hoc signature so they do not depend on a certificate that exists only on the build machine.

### GNOME

For GNOME extension development and debugging notes, see [gnome-extension/DEVELOPING.md](gnome-extension/DEVELOPING.md).

## Roadmap

See [SPEC.md](SPEC.md) for current behaviour. Out of scope for now: settings UI, custom hotkeys, per-app cycle, moving windows between Spaces.

## About the name

The `u` is `µ` — it's HyperSwitch in a smaller package.

## License

[MIT](LICENSE). Not affiliated with HyperSwitch or Bahoom.
