import AppKit
import CoreGraphics

private let kVK_Escape: CGKeyCode = 53
private let kVK_Q: CGKeyCode = 12
private let kVK_W: CGKeyCode = 13
private let kVK_M: CGKeyCode = 46
private let kVK_Comma: CGKeyCode = 43

final class EventTap {
    var onTrigger: (() -> Void)?
    var onTriggerOverview: (() -> Void)?
    var onCycle: ((Bool) -> Void)?  // backward = true
    var onEscape: (() -> Void)?
    var onCommit: (() -> Void)?
    var onQuit: (() -> Void)?
    var onCloseWindow: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onSettings: (() -> Void)?
    var isActive: () -> Bool = { false }
    // While true, every key is passed through untouched (shortcut recording).
    var isSuspended: () -> Bool = { false }

    var primaryHotkey: Hotkey = .primaryDefault
    var overviewHotkey: Hotkey = .overviewDefault

    private var tap: CFMachPort?
    // The shortcut that opened the current session, used to cycle and to know
    // which release commits. nil when idle.
    private var session: Hotkey?

    func install() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let cb: CGEventTapCallBack = { _, type, event, ctx in
            let me = Unmanaged<EventTap>.fromOpaque(ctx!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: cb,
            userInfo: userInfo
        ) else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // A shortcut recorder is capturing keys; let them all through.
        if isSuspended() { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let shift = flags.contains(.maskShift)
        let option = flags.contains(.maskAlternate)
        let control = flags.contains(.maskControl)

        let activeNow = isActive()
        // A session ends through commit or cancel; clear the remembered shortcut
        // so the next press starts fresh.
        if !activeNow { session = nil }

        if type == .keyDown {
            // Cycling: the trigger key again while its modifiers are still held.
            if activeNow, let session, keycode == session.keyCode {
                print("tap: cycle (shift=\(shift))")
                onCycle?(shift)
                return nil
            }
            if !activeNow {
                if primaryHotkey.matches(keycode, flags) {
                    print("tap: trigger \(primaryHotkey.displayString)")
                    session = primaryHotkey
                    onTrigger?()
                    return nil
                }
                if overviewHotkey.matches(keycode, flags) {
                    print("tap: trigger overview \(overviewHotkey.displayString)")
                    session = overviewHotkey
                    onTriggerOverview?()
                    return nil
                }
            }
            if activeNow, keycode == kVK_Escape {
                print("tap: escape")
                session = nil
                onEscape?()
                return nil
            }
            // While the overlay is up, Cmd+Q / Cmd+W / Cmd+M / Cmd+, act on the
            // switcher instead of the frontmost app. Swallow them even with
            // extra modifiers (Cmd+Shift+Q is logout) so nothing leaks through.
            if activeNow, flags.contains(.maskCommand),
               keycode == kVK_Q || keycode == kVK_W || keycode == kVK_M || keycode == kVK_Comma {
                let plain = !shift && !option && !control
                let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if plain, !repeating {
                    switch keycode {
                    case kVK_Q:
                        print("tap: quit selected app")
                        onQuit?()
                    case kVK_W:
                        print("tap: close selected window")
                        onCloseWindow?()
                    case kVK_Comma:
                        print("tap: open settings")
                        session = nil
                        onSettings?()
                    default:
                        print("tap: minimize selected window")
                        onMinimize?()
                    }
                }
                return nil
            }
        } else if type == .flagsChanged {
            guard activeNow, let session else { return Unmanaged.passUnretained(event) }
            if session.isReleased(flags) {
                print("tap: commit (hotkey released, flags=\(flags.rawValue))")
                self.session = nil
                onCommit?()
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
