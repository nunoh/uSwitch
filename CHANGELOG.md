# Changelog

## Unreleased

### ✨ Features
- Settings window (menu bar → Settings…, or Cmd+, while the switcher is open) with a shortcut recorder for both hotkeys, minimized-window behaviour, thumbnail size, overview scaling, and flick delay; persisted in UserDefaults and applied live
- Minimized windows stay in the switcher as a compact icon + title strip below the active tiles, shown but skipped by the Tab cycle
- All-Spaces overview on <kbd>Option</kbd>+<kbd>Tab</kbd>, grouping windows by Space with the current Space marked
- Selecting a minimized window restores it; selecting a window on another Space switches to that Space

### 🔧 Improvements
- Cmd+Minimize moves the tile into the minimized strip instead of dropping it
- All-Spaces overview renders sections in Space order (current marked, not moved to the front)
- All-Spaces overview starts on the current Space and renders other Spaces slightly smaller
- Minimized strip shows smaller text that scales down to fit before truncating
- Overlay scrolls vertically when it is taller than the screen

### 🐛 Fixes
- Restore front-to-back (MRU) window order so a single switcher press moves to the previous window again — `CGWindowListCopyWindowInfo(.optionAll)` does not preserve z-order
- All-Spaces overview no longer lists leftover WindowServer surfaces (Calendar kept a dozen) as phantom windows
- All-Spaces overview lists windows that live on other Spaces again; membership now comes from WindowServer's per-Space window lists

## 2026-04-28 (v0.2)

### ✨ Features
- About panel with version and GitHub links
- Changelog viewer

### 🔧 Improvements
- Multi-row overlay when tiles overflow the screen
- Space-aware window list (no stale entries after switching Spaces)
- Cmd+W closes About / Changelog
- Cmd+Q no longer quits from the menu

## 2026-04-27 (v0.1)

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
