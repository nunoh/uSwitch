# uSwitch — SPEC

## Trigger
- Cmd+Tab opens overlay.
- Overlay opens on the display under the pointer, and lists only windows on
  that display's current Space — other monitors' Spaces never leak in.
- MRU order — second item is the most-recently-used window.

## Preview
- Each entry shows a live thumbnail (captured at open time, not cached).
- All thumbnails rendered at equal size regardless of source window dimensions.
- App icon overlaid as a badge on each thumbnail.

## Selection
- Tab cycles forward (Cmd held).
- Shift+Tab cycles backward.
- Releasing Cmd raises the selected window.

## Cancel
- Escape dismisses without switching.
- Escape is swallowed — must not reach the system or any other app.
- Specifically: global Cmd+Escape binding (iTerm) must not fire while overlay is open.

## Out of scope (v1)
- Windows on other Spaces.
- Settings UI, custom hotkey, per-app cycle.
