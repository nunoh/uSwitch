# Changelog

## [0.3.0](https://github.com/nunoh/uSwitch/compare/v0.2.0...v0.3.0) (2026-09-26)


### ✨ Features

* act on the selected window from the switcher ([f5d8322](https://github.com/nunoh/uSwitch/commit/f5d8322278361a0229e33a20b711de0165258dd3))
* add gnome shell extension port ([a63e716](https://github.com/nunoh/uSwitch/commit/a63e716cd3df4e9b635eb226f9a95b25c1c64981))
* all-Spaces overview, minimized strip, and a Settings window ([6b946e1](https://github.com/nunoh/uSwitch/commit/6b946e13495311e683e489371e6c1f7e58032d9f))
* check GitHub daily for a newer release ([#7](https://github.com/nunoh/uSwitch/issues/7)) ([0a59932](https://github.com/nunoh/uSwitch/commit/0a59932836f6bd4519cb20eddb011a9add65c646))
* flick past gnome switcher without flashing the popup ([a83fec5](https://github.com/nunoh/uSwitch/commit/a83fec5b082e596b28bcfc7fba0376e205811443))
* tint the current Space in the overview ([#4](https://github.com/nunoh/uSwitch/issues/4)) ([2f91ef1](https://github.com/nunoh/uSwitch/commit/2f91ef1d092e1af3850732bc311fb1e864852441))
* toggle the all-Spaces overview with S or Cmd+F ([#2](https://github.com/nunoh/uSwitch/issues/2)) ([8a64070](https://github.com/nunoh/uSwitch/commit/8a64070ec16c81eeb084340fa498e894ca06c1e1))


### 🐛 Fixes

* always live-read current space to avoid stale cache ([7bc8a8e](https://github.com/nunoh/uSwitch/commit/7bc8a8ee3e72a989e3a6f06225dddf912e959b4a))
* cycle backward on Shift+Tab in gnome switcher ([9362da4](https://github.com/nunoh/uSwitch/commit/9362da4db15797aa8babcee75af4a18e9d3c4ad6))
* fall back to legacy activate when source app refuses to yield ([24dd547](https://github.com/nunoh/uSwitch/commit/24dd547dd3649e7652313de65fba7cfae0454031))
* hide agent apps and floating panels from the switcher ([830ff91](https://github.com/nunoh/uSwitch/commit/830ff9162f2f90517f3e116308065545862fad53))
* hide Chromium internal windows from the switcher ([#3](https://github.com/nunoh/uSwitch/issues/3)) ([151c769](https://github.com/nunoh/uSwitch/commit/151c7693aaeb33d3c7dd1f4c5b0f7fbe0484cde7))
* keep window titles at one font size ([8726ebc](https://github.com/nunoh/uSwitch/commit/8726ebcfa4f690cccbb404b8f36637cdda2c9b1e))
* raise the exact window instead of matching by title ([5271edf](https://github.com/nunoh/uSwitch/commit/5271edf1362e2c89e43bfba578a6614189d603b1))
* scope switcher to the current display's space ([4fb86ef](https://github.com/nunoh/uSwitch/commit/4fb86ef2b8376d9c512e44ff9b2ac20cef61110f))
* set accessory activation policy before permission checks ([b338e5e](https://github.com/nunoh/uSwitch/commit/b338e5e50df8edcc03e68527520b0df8192c07ef))
* switch between windows of the same app in Chrome ([cc3e3ba](https://github.com/nunoh/uSwitch/commit/cc3e3bafe8430a7ebd0d59f6148f387094ca3fe2))

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
