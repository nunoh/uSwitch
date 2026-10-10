# uSwitch — SPEC

## Trigger
- The primary shortcut (default Cmd+Tab) opens the switcher; the overview
  shortcut (default Option+Tab) opens the all-Spaces overview.
- The overlay opens on the display under the pointer and lists only windows on
  that display's Spaces — other monitors' Spaces never leak in.
- The switcher lists the current Space. The overview lists every Space on that
  display, grouped under a labelled header, in Space order.
- MRU order — second item is the most-recently-used window.

## Preview
- Each entry shows a live thumbnail (captured at open time, not cached).
- All thumbnails rendered at equal size regardless of source window dimensions.
- App icon overlaid as a badge on each thumbnail.
- Windows whose live thumbnail can't be captured (on another Space) fall back
  to their cached thumbnail, then to the app icon.

## Minimized windows
- Minimized windows are listed, not hidden.
- They render as a compact icon + title strip (no thumbnail) beneath the active
  tiles of their Space, under a small "Minimized" caption. The strip is smaller
  than a full tile.
- Tab skips them by default. Click one to restore and raise it, or press Fn
  while the switcher is open to step through minimized windows.
- Fn alone never opens the overlay. Holding Fn repeats cycling using the macOS
  keyboard repeat delay and interval. Releasing it, committing, or canceling
  stops repeat.
- Restoring happens before raising; a minimized window cannot be focused in place.

## Overview grouping
- One section per Space, in Space order (Space 1, Space 2, …), labelled "Space N"
  (fullscreen Spaces keep their name). The active one is tinted; empty Spaces
  stay listed with a "No windows" note.
- Non-current Spaces render slightly smaller, so the active Space stands out.
- Membership comes from WindowServer's per-Space lists: the Space's visible
  windows, plus any window Accessibility confirms as minimized. Leftover
  surfaces and Chromium-style internal windows are excluded.
- Sticky / all-Spaces windows are shown once, in the current Space.
- The default selection is the previous window of the current Space, matching
  the plain switcher.

## Selection
- Tab cycles forward (hold modifier).
- Shift+Tab (with the hold modifier still down) cycles backward.
- Pressing Fn steps through minimized windows. Fn plus either main shortcut
  opens an all-window cycle.
- Releasing the hold modifier (Cmd for the switcher, Option for the overview)
  raises the selected window.
- Selecting a window on another Space switches to that Space.
- Cmd+Q quits the selected app and keeps the overlay open.
- Cmd+W closes the selected window and keeps the overlay open.
- Cmd+M minimizes the selected window; the tile moves into the minimized strip
  and the overlay stays open.
- Cmd+1…9 switches straight to the Nth active window of the current Space
  (in visual order); the minimized strip and other Spaces are not addressable
  this way.
- Cmd+, dismisses without switching and opens the Settings window.
- S or Cmd+F toggles between the current-Space switcher and the all-Spaces
  overview while the overlay stays open; the selected window is preserved when
  present in both.
- After a close/quit the window list is refreshed; if no windows remain the
  overlay closes.

## Cancel
- Escape dismisses without switching.
- Escape is swallowed — must not reach the system or any other app.
- Specifically: global Cmd+Escape binding (iTerm) must not fire while overlay is open.

## Settings
- A Settings window (menu bar → Settings…, or Cmd+,) holds:
  - the two shortcuts, with a recorder that suspends the event tap while capturing;
  - whether minimized windows are shown, and whether Tab cycles through them;
  - thumbnail size (small / medium / large);
  - how much smaller non-current Spaces render in the overview;
  - the flick delay.
- Values persist in UserDefaults and apply live, without a relaunch.
- A "Reset to Defaults" button restores the shipped behaviour.

## Out of scope (v1)
- Per-app cycle rules.
- Rearranging or moving windows between Spaces from the switcher.
