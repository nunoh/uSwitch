# Changelog

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
