import Clutter from 'gi://Clutter';
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

const TILE_WIDTH = 180;
const TILE_HEIGHT = 120;
const ICON_SIZE = 52;
const TILE_SPACING = 12;
const SCREEN_MARGIN = 80;

const UModifier = {
    SHIFT: Clutter.ModifierType.SHIFT_MASK,
    ALT: Clutter.ModifierType.MOD1_MASK,
    SUPER: Clutter.ModifierType.SUPER_MASK,
    HYPER: Clutter.ModifierType.HYPER_MASK,
    META: Clutter.ModifierType.META_MASK,
};

function primaryModifier(mask) {
    for (const modifier of [UModifier.ALT, UModifier.SUPER, UModifier.META, UModifier.HYPER]) {
        if (mask & modifier)
            return modifier;
    }

    return 0;
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
    _init(windows, reversed, bindingMask) {
        super._init({
            reactive: true,
            can_focus: true,
            layout_manager: new Clutter.BinLayout(),
            visible: false,
        });

        this._windows = windows;
        this._modifierMask = primaryModifier(bindingMask);
        this._selectedIndex = this._initialSelection(reversed);
        this._tiles = [];
        this._signals = [];
        this._modalGrab = null;

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
        this._position();
        this.visible = true;
        this.grab_key_focus();

        this._signals.push(
            this.connect('key-press-event', this._onKeyPress.bind(this)),
            this.connect('key-release-event', this._onKeyRelease.bind(this))
        );

        return true;
    }

    cycle(backward) {
        if (this._windows.length === 0)
            return;

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
        const bindingMask = binding && typeof binding.get_mask === 'function'
            ? binding.get_mask()
            : UModifier.SUPER;

        if (this._popup) {
            this._popup.cycle(reversed);
            return;
        }

        const windows = this._windowsOnCurrentWorkspace();
        if (windows.length === 0)
            return;

        this._popup = new USwitchPopup(windows, reversed, bindingMask);
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
