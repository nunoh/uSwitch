# Developing the GNOME extension

Notes for hacking on the GNOME Shell port (`uswitch@nh.com`). Not user-facing.
Findings here are specific to Ubuntu 26.04 / GNOME Shell 50.1 / Wayland.

## Install & enable

```sh
make install-gnome-extension          # pack + install into ~/.local/share/...
gnome-extensions enable uswitch@nh.com
```

`make install-gnome-extension` packs to `~/.cache/uswitch/` and installs with
`gnome-extensions install --force`. Everything is user-level — **never run it
with `sudo`.** A root-owned build artifact in sticky `/tmp` (from a stray sudo
run) is what wedges the install with `Operation not permitted`; the cache-dir
output path avoids that, but if you hit it, `sudo rm` the leftover once.

## The reload loop: log out / log in

There is **no in-session reload on this setup.** After editing `extension.js`:

```
edit -> make install-gnome-extension -> log out / log in -> test
```

Everything lighter was tried and does not work here:

| Approach | Why it fails |
| --- | --- |
| Restart shell in place | Impossible on Wayland — the shell *is* the display server |
| Nested shell (`gnome-shell --wayland`) | mutter 50.1 has no nested backend (`nm -D` shows none); it tries to be a full display server and collides with the live session (`Failed to take control of the session: EBUSY`) |
| GNOME on Xorg (`Alt+F2` → `r`) | Ubuntu 26.04 is Wayland-only; no Xorg session installed |
| `gnome-extensions disable`/`enable` | Re-runs the lifecycle but does not re-import the JS module |
| `org.gnome.Shell.Extensions.ReloadExtension` D-Bus | Introspected but not implemented on this build |

A headless shell (`--headless --virtual-monitor`) plus a remote-desktop viewer
would avoid the logout, but it's far too much ceremony for a switcher you need
to see. Batch your edits and accept the logout as the test step.

## Debugging

The shell logs to the journal. Watch the extension while reproducing:

```sh
journalctl --user -f | grep -iE 'uswitch|JS ERROR'
```

Drop a temporary `log('uSwitch: ...')` into the code — it lands in the journal
with the `uswitch` substring above. Remove it before committing.

## Gotcha: the modifier mask is virtual, the live state is resolved

The trap that made the switcher commit instantly instead of holding open:

- `binding.get_mask()` reports a **virtual** modifier — for `<Super>Tab` that's
  `Clutter.ModifierType.SUPER_MASK` = `1 << 26` = `67108864`.
- `global.get_pointer()` reports the **resolved** modifier actually held — Super
  comes back as `MOD4_MASK` = `1 << 6` = `64`.

`67108864 & 64 == 0`, so "is the trigger still held?" was always false and the
popup committed on the first key event. Fix: at `show()` time, sample the live
held modifier from `global.get_pointer()` (Super *is* down then), reduce it to
its lowest bit, and compare releases against that same value. Self-consistent,
so it no longer matters that the binding's mask is a different representation.

## Trigger key

The extension overrides both `switch-applications` (`<Alt>Tab`) and
`switch-windows` (`<Super>Tab`), so either opens the uSwitch popup and every
window gets its own tile. Super is the Cmd-position key (macOS muscle memory);
Alt+Tab is also routed here because GNOME's native `switch-applications` groups
windows by app, hiding extra windows of the same app. All four accelerators live
in `KEYBINDINGS`; `disable()` restores them to GNOME's native handler.
