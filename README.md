# uswitch
macOS window switcher. A HyperSwitch replacement that doesn't leak Escape to the system.

## Dev

```sh
make dev
```

Debug-builds, drops the binary into `dist/uswitch.app`, ad-hoc signs, kills any running instance, and relaunches. The bundle id is stable (`com.nh.uswitch`) so Accessibility / Screen Recording grants persist across rebuilds.

First run: macOS will prompt for **Accessibility** (required) and **Screen Recording** (required for thumbnails). Grant both in System Settings → Privacy & Security, then `make dev` again.

## PRD

### Trigger
- Cmd+Tab opens overlay.
- Overlay lists windows on the current Space.
- MRU order — second item is the most-recently-used window.

### Preview
- Each entry shows a live thumbnail (captured at open time, not cached).
- All thumbnails rendered at equal size regardless of source window dimensions.
- App icon overlaid as a badge on each thumbnail.

### Selection
- Tab cycles forward (Cmd held).
- Shift+Tab cycles backward.
- Releasing Cmd raises the selected window.

### Cancel
- Escape dismisses without switching.
- Escape is swallowed — must not reach the system or any other app.
- Specifically: global Cmd+Escape binding (iTerm) must not fire while overlay is open.

### Out of scope (v1)
- Windows on other Spaces.
- Settings UI, custom hotkey, per-app cycle, multi-monitor rules.
