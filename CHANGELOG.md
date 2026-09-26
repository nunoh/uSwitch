# Changelog

## [0.3.1](https://github.com/nunoh/uSwitch/compare/v0.3.0...v0.3.1) (2026-09-26)


### 🐛 Fixes

* keep macOS permissions across updates ([#10](https://github.com/nunoh/uSwitch/issues/10)) ([92b64ba](https://github.com/nunoh/uSwitch/commit/92b64ba84ad4bf7d70a3eab6a1a20ab96c604f50))

## [0.3.0](https://github.com/nunoh/uSwitch/compare/v0.2.0...v0.3.0) (2026-09-26)

### ✨ Features
- All-Spaces overview on <kbd>Option</kbd>+<kbd>Tab</kbd>, grouping windows by Space with the current Space marked
- Press S or Cmd+F while the switcher is open to toggle the all-Spaces overview on and off, keeping the selected window
- Settings window (menu bar → Settings…, or Cmd+, while the switcher is open) with a shortcut recorder for both hotkeys, minimized-window behaviour, thumbnail size, overview scaling, flick delay, and the update check; persisted in UserDefaults and applied live
- Minimized windows stay in the switcher as a compact icon + title strip below the active tiles, shown but skipped by the Tab cycle
- Selecting a minimized window restores it; selecting a window on another Space switches to that Space
- Cmd+Q, Cmd+W, and Cmd+M quit, close, or minimize the selected window while the switcher stays open
- Daily check for a newer release, with "Update Available" and "Check for Updates…" in the menu bar
- GNOME Shell extension port, including the flick past the switcher without flashing the popup
- Install with Homebrew: `brew install --cask nunoh/tap/uswitch`

### 🔧 Improvements
- Cmd+Minimize moves the tile into the minimized strip instead of dropping it
- All-Spaces overview renders sections in Space order (current marked, not moved to the front)
- All-Spaces overview starts on the current Space and renders other Spaces slightly smaller
- All-Spaces overview tints the current Space's section subtly, in addition to the "current" badge
- Minimized strip shows smaller text that scales down to fit before truncating
- Overlay scrolls vertically when it is taller than the screen, with indicators hidden so the scrollbar no longer flashes during expansion
- Releases ship as a DMG and zip with SHA-256 checksums and a build attestation

### 🐛 Fixes
- Window titles keep one font size; long titles truncate in the middle instead of shrinking
- Switch between windows of the same app in Chrome
- Raise the exact window instead of matching by title
- Hide agent apps and floating panels from the switcher
- Hide Chromium internal (empty-title helper) windows from the switcher
- Scope the switcher to the current display's Space, and always read the current Space live
- Fall back to legacy activation when the source app refuses to yield
- Set the accessory activation policy before permission checks
- Restore front-to-back (MRU) window order so a single switcher press moves to the previous window again
- All-Spaces overview no longer lists leftover WindowServer surfaces (Calendar kept a dozen) as phantom windows
- All-Spaces overview lists windows that live on other Spaces again
- GNOME: Shift+Tab cycles backward

## 0.2.0 (2026-04-28)

### ✨ Features
- About panel with version and GitHub links
- Changelog viewer

### 🔧 Improvements
- Multi-row overlay when tiles overflow the screen
- Space-aware window list (no stale entries after switching Spaces)
- Cmd+W closes About / Changelog
- Cmd+Q no longer quits from the menu

## 0.1.0 (2026-04-27)

### ✨ Features
- HyperSwitch-style Cmd+Tab replacement: live window thumbnails for the current Space
- Tiles show the app icon overlaid on the window thumbnail, with the title underneath
- Esc cancels the switcher and is swallowed — won't leak to system shortcuts (e.g. iTerm Cmd+Esc)
- Cmd+Shift+Tab cycles backward
- Background thumbnail cache keeps the overlay opening instantly; refreshed silently as you switch apps
- Menu bar icon with Quit

### 🏗️ Under the hood
- Swift Package executable targeting macOS 13+
- `make cloc` target for line counts
