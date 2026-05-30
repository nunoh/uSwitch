import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const KEYBINDINGS = [
    'switch-windows',
    'switch-windows-backward',
];

const NATIVE_KEYBINDINGS = [
    'switch-applications',
    'switch-applications-backward',
];

const SWITCHER_ACTION_MODE = Shell.ActionMode.NORMAL | Shell.ActionMode.POPUP;

// How long the popup lingers before auto-committing when opened without a held
// modifier (e.g. triggered via a tap binding). Matches GNOME's switcher.
const NO_MODS_TIMEOUT = 1500;

// Grace period before the popup becomes visible. A fast Super+Tab flick (tap
// Tab, release Super within this window) switches to the previous window
// without ever flashing the UI. Cycling again reveals it immediately. Kept
// short so a deliberate open doesn't feel laggy (GNOME's own default is 150ms).
const POPUP_DELAY = 50;

// The "hold to browse" modifiers we track. binding.get_mask() reports a virtual
// modifier (e.g. SUPER_MASK = 1<<26) that never matches global.get_pointer()'s
// resolved state (Super = MOD4_MASK = 1<<6), so we sample the live state at open
// time instead and watch these bits. Shift/lock are excluded: Shift selects
// direction, and lock keys (Caps/Num) must not pin the popup open.
const HOLD_MODS =
    Clutter.ModifierType.CONTROL_MASK |
    Clutter.ModifierType.MOD1_MASK |
    Clutter.ModifierType.MOD4_MASK |
    Clutter.ModifierType.MOD5_MASK |
    Clutter.ModifierType.SUPER_MASK |
    Clutter.ModifierType.HYPER_MASK |
    Clutter.ModifierType.META_MASK;

const TILE_WIDTH = 180;
const TILE_HEIGHT = 120;
const ICON_SIZE = 52;
const TILE_SPACING = 12;
const SCREEN_MARGIN = 80;

// Reduce a modifier mask to its lowest set bit, so a multi-modifier state
// (e.g. Super+Shift) collapses to the single "hold" modifier we watch.
function primaryModifier(mask) {
    if (mask === 0)
        return 0;

    let primary = 1;
    while (mask > 1) {
        mask >>= 1;
        primary <<= 1;
    }
    return primary;
}

const UWindowTile = GObject.registerClass(
class UWindowTile extends St.BoxLayout {
    _init(metaWindow, selected) {
        super._init({
            style_class: 'uswitch-tile',
            vertical: true,
            x_expand: false,
            y_expand: false,
        });

        this._metaWindow = metaWindow;

        this._preview = new St.Widget({
            style_class: 'uswitch-preview',
            width: TILE_WIDTH,
            height: TILE_HEIGHT,
            x_expand: false,
            y_expand: false,
            clip_to_allocation: true,
        });
        this.add_child(this._preview);

        this._addLiveClone();
        this._addAppIcon();

        const label = new St.Label({
            style_class: 'uswitch-label',
            text: this._labelText(),
        });
        this.add_child(label);

        this.setSelected(selected);
    }

    setSelected(selected) {
        if (selected)
            this.add_style_pseudo_class('selected');
        else
            this.remove_style_pseudo_class('selected');
    }

    _addLiveClone() {
        const windowActor = this._metaWindow.get_compositor_private();
        if (!windowActor)
            return;

        const rect = this._metaWindow.get_buffer_rect();
        const scale = Math.min(
            (TILE_WIDTH - 10) / Math.max(rect.width, 1),
            (TILE_HEIGHT - 10) / Math.max(rect.height, 1)
        );
        const width = rect.width * scale;
        const height = rect.height * scale;

        const clone = new Clutter.Clone({
            source: windowActor,
            reactive: false,
            width: rect.width,
            height: rect.height,
            scale_x: scale,
            scale_y: scale,
            x: Math.floor((TILE_WIDTH - width) / 2),
            y: Math.floor((TILE_HEIGHT - height) / 2),
        });
        this._preview.add_child(clone);
    }

    _addAppIcon() {
        const app = Shell.WindowTracker.get_default().get_window_app(this._metaWindow);
        const icon = app?.create_icon_texture(ICON_SIZE);
        if (!icon)
            return;

        icon.add_style_class_name('uswitch-app-icon');
        icon.set_position(
            Math.floor((TILE_WIDTH - ICON_SIZE) / 2),
            Math.floor((TILE_HEIGHT - ICON_SIZE) / 2)
        );
        this._preview.add_child(icon);
    }

    _labelText() {
        const title = this._metaWindow.get_title();
        if (title)
            return title;

        const app = Shell.WindowTracker.get_default().get_window_app(this._metaWindow);
        return app?.get_name() ?? this._metaWindow.get_wm_class() ?? '';
    }
});

const USwitchPopup = GObject.registerClass(
class USwitchPopup extends St.Widget {
    _init(windows, reversed) {
        super._init({
            reactive: true,
            can_focus: true,
            layout_manager: new Clutter.BinLayout(),
            visible: false,
        });

        this._windows = windows;
        this._modifierMask = 0; // sampled from the live held modifier in show()
        this._selectedIndex = this._initialSelection(reversed);
        this._tiles = [];
        this._signals = [];
        this._modalGrab = null;
        this._noModsTimeoutId = 0;
        this._showTimeoutId = 0;

        this.add_constraint(new Clutter.BindConstraint({
            source: global.stage,
            coordinate: Clutter.BindCoordinate.ALL,
        }));

        this._surface = new St.BoxLayout({
            style_class: 'uswitch-popup',
            vertical: true,
        });
        this.add_child(this._surface);

        this._render();
    }

    show() {
        Main.uiGroup.add_child(this);

        const grab = Main.pushModal(this, {actionMode: Shell.ActionMode.POPUP});
        if (!grab) {
            this.destroy();
            return false;
        }

        this._modalGrab = grab;
        // Mapped (visible) but fully transparent, so it keeps the keyboard grab
        // and receives Tab/Escape/release while invisible. A quick flick commits
        // and destroys before the delay fires, so the UI never paints.
        this.opacity = 0;
        this.visible = true;
        this._position();
        this.grab_key_focus();

        this._signals.push(
            this.connect('key-press-event', this._onKeyPress.bind(this)),
            this.connect('key-release-event', this._onKeyRelease.bind(this))
        );

        this._showTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, POPUP_DELAY, () => {
            this._showTimeoutId = 0;
            this._showImmediately();
            return GLib.SOURCE_REMOVE;
        });

        // Sample the modifier physically held right now (the trigger key, e.g.
        // Super) and track exactly those bits. This is self-consistent with the
        // release check below, unlike binding.get_mask()'s virtual modifier.
        const [, , mods] = global.get_pointer();
        this._modifierMask = primaryModifier(mods & HOLD_MODS);

        // Race: the modifier may already be up by the time we grabbed (or it was
        // a tap-style trigger). Fall back to the no-mods timeout so the popup is
        // still dismissable instead of committing to nothing.
        if (this._modifierMask === 0)
            this._resetNoModsTimeout();

        return true;
    }

    _showImmediately() {
        if (this._showTimeoutId) {
            GLib.source_remove(this._showTimeoutId);
            this._showTimeoutId = 0;
        }
        this.opacity = 255;
    }

    _resetNoModsTimeout() {
        if (this._noModsTimeoutId)
            GLib.source_remove(this._noModsTimeoutId);

        this._noModsTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, NO_MODS_TIMEOUT, () => {
            this._noModsTimeoutId = 0;
            this.commit();
            return GLib.SOURCE_REMOVE;
        });
    }

    cycle(backward) {
        if (this._windows.length === 0)
            return;

        // Cycling past the initial pick is intent to browse — reveal now.
        this._showImmediately();

        const step = backward ? -1 : 1;
        this._selectedIndex = (this._selectedIndex + step + this._windows.length) % this._windows.length;
        this._syncSelection();
    }

    commit() {
        const window = this._windows[this._selectedIndex];
        this.destroy();

        if (!window)
            return;

        window.unminimize();
        window.activate(global.get_current_time());
        window.raise();
    }

    cancel() {
        this.destroy();
    }

    destroy() {
        if (this._showTimeoutId) {
            GLib.source_remove(this._showTimeoutId);
            this._showTimeoutId = 0;
        }

        if (this._noModsTimeoutId) {
            GLib.source_remove(this._noModsTimeoutId);
            this._noModsTimeoutId = 0;
        }

        for (const id of this._signals)
            this.disconnect(id);
        this._signals = [];

        if (this._modalGrab) {
            Main.popModal(this._modalGrab);
            this._modalGrab = null;
        }

        super.destroy();
    }

    _initialSelection(reversed) {
        if (this._windows.length < 2)
            return 0;
        return reversed ? this._windows.length - 1 : 1;
    }

    _render() {
        const monitor = Main.layoutManager.currentMonitor ?? Main.layoutManager.primaryMonitor;
        const availableWidth = monitor.width - SCREEN_MARGIN * 2;
        const columns = Math.max(1, Math.floor((availableWidth + TILE_SPACING) / (TILE_WIDTH + TILE_SPACING)));

        let row = null;
        this._windows.forEach((window, index) => {
            if (index % columns === 0) {
                row = new St.BoxLayout({
                    style_class: 'uswitch-row',
                    vertical: false,
                });
                this._surface.add_child(row);
            }

            const tile = new UWindowTile(window, index === this._selectedIndex);
            this._tiles.push(tile);
            row.add_child(tile);
        });
    }

    _position() {
        const monitor = Main.layoutManager.currentMonitor ?? Main.layoutManager.primaryMonitor;
        this._surface.ensure_style();

        const [minWidth, naturalWidth] = this._surface.get_preferred_width(-1);
        const [minHeight, naturalHeight] = this._surface.get_preferred_height(naturalWidth);
        const width = Math.max(minWidth, naturalWidth);
        const height = Math.max(minHeight, naturalHeight);

        this._surface.set_size(width, height);
        this._surface.set_position(
            Math.floor(monitor.x + (monitor.width - width) / 2),
            Math.floor(monitor.y + (monitor.height - height) / 2)
        );
    }

    _syncSelection() {
        this._tiles.forEach((tile, index) => tile.setSelected(index === this._selectedIndex));
    }

    _onKeyPress(actor, event) {
        const symbol = event.get_key_symbol();
        const state = event.get_state();

        if (symbol === Clutter.KEY_Escape) {
            this.cancel();
            return Clutter.EVENT_STOP;
        }

        if (symbol === Clutter.KEY_Tab || symbol === Clutter.KEY_ISO_Left_Tab) {
            this.cycle((state & Clutter.ModifierType.SHIFT_MASK) !== 0);
            if (this._noModsTimeoutId)
                this._resetNoModsTimeout();
            return Clutter.EVENT_STOP;
        }

        if (symbol === Clutter.KEY_Return || symbol === Clutter.KEY_KP_Enter ||
            symbol === Clutter.KEY_ISO_Enter || symbol === Clutter.KEY_space) {
            this.commit();
            return Clutter.EVENT_STOP;
        }

        return Clutter.EVENT_STOP;
    }

    _onKeyRelease(actor, event) {
        if (this._modifierMask && this._isModifierReleased()) {
            this.commit();
            return Clutter.EVENT_STOP;
        }

        return Clutter.EVENT_STOP;
    }

    _isModifierReleased() {
        const [, , mods] = global.get_pointer();
        return (mods & this._modifierMask) === 0;
    }
});

export default class USwitchExtension extends Extension {
    enable() {
        this._popup = null;
        this._restoreKeybindings(NATIVE_KEYBINDINGS);
        this._overrideKeybindings();
    }

    disable() {
        this._popup?.destroy();
        this._popup = null;
        this._restoreKeybindings(KEYBINDINGS.concat(NATIVE_KEYBINDINGS));
    }

    _overrideKeybindings() {
        for (const name of KEYBINDINGS) {
            Main.wm.setCustomKeybindingHandler(
                name,
                SWITCHER_ACTION_MODE,
                this._startSwitcher.bind(this)
            );
        }
    }

    _restoreKeybindings(keybindings) {
        const nativeHandler = Main.wm._startSwitcher?.bind(Main.wm);
        if (!nativeHandler)
            return;

        for (const name of keybindings) {
            Main.wm.setCustomKeybindingHandler(
                name,
                SWITCHER_ACTION_MODE,
                nativeHandler
            );
        }
    }

    _startSwitcher(display, window, binding) {
        if (Main.wm._workspaceSwitcherPopup)
            Main.wm._workspaceSwitcherPopup.destroy();

        const bindingName = binding && typeof binding.get_name === 'function'
            ? binding.get_name()
            : '';
        const reversed = bindingName.endsWith('-backward') ||
            (typeof binding?.is_reversed === 'function' && binding.is_reversed());

        if (this._popup) {
            this._popup.cycle(reversed);
            return;
        }

        const windows = this._windowsOnCurrentWorkspace();
        if (windows.length === 0)
            return;

        this._popup = new USwitchPopup(windows, reversed);
        this._popup.connect('destroy', () => {
            this._popup = null;
        });
        if (!this._popup.show())
            this._popup = null;
    }

    _windowsOnCurrentWorkspace() {
        const workspace = global.workspace_manager.get_active_workspace();
        return global.display
            .get_tab_list(Meta.TabList.NORMAL, workspace)
            .filter(window => window.showing_on_its_workspace())
            .filter(window => !window.is_hidden())
            .filter(window => !window.is_skip_taskbar());
    }
}
