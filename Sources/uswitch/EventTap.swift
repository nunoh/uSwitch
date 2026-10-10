import AppKit
import CoreGraphics

private let kVK_Escape: CGKeyCode = 53
private let kVK_Q: CGKeyCode = 12
private let kVK_W: CGKeyCode = 13
private let kVK_M: CGKeyCode = 46
private let kVK_S: CGKeyCode = 1
private let kVK_F: CGKeyCode = 3
private let kVK_Comma: CGKeyCode = 43
private let kVK_Function: CGKeyCode = 63

// Number-row digits, as they appear in Hotkey.keyName. Cmd + one of these jumps
// straight to that tile while the overlay is open.
private let kVK_Digits: [CGKeyCode: Int] = [
    18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
]

final class EventTap {
    var onTrigger: (() -> Void)?
    var onTriggerOverview: (() -> Void)?
    var onTriggerAll: (() -> Void)?
    var onTriggerOverviewAll: (() -> Void)?
    var onCycle: ((Bool) -> Void)?  // backward = true
    var onCycleMinimized: ((Bool) -> Void)?  // backward = true
    // Cmd + 1…9 while open: select the Nth active tile of the current Space.
    var onSelectNumber: ((Int) -> Void)?
    var onEscape: (() -> Void)?
    var onCommit: (() -> Void)?
    var onQuit: (() -> Void)?
    var onCloseWindow: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onSettings: (() -> Void)?
    var onToggleMode: (() -> Void)?
    var isActive: () -> Bool = { false }
    // While true, every key is passed through untouched (shortcut recording).
    var isSuspended: () -> Bool = { false }
    // Called after the tap removed itself because Accessibility was revoked.
    var onTrustRevoked: (() -> Void)?

    var primaryHotkey: Hotkey = .primaryDefault
    var overviewHotkey: Hotkey = .overviewDefault

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    // The shortcut that opened the current session, used to cycle and to know
    // which release commits. nil when idle.
    private var session: Hotkey?
    // Shift-only hotkeys have no commit modifiers; release Shift to commit.
    private var sessionReleaseOnShift = false
    private var fnWasDown = false
    private var minimizedRepeatTimer: Timer?
    private var repeatBackward = false

    deinit { minimizedRepeatTimer?.invalidate() }

    // Modifier keys do not generate key repeats, so use the same delay and
    // interval as macOS keyboard repeat. Each explicit Tab restarts the delay
    // to avoid cycling twice while Tab itself is repeating.
    private func startMinimizedRepeat() {
        stopMinimizedRepeat()
        guard isActive(), session != nil, !isSuspended() else { return }
        let timer = Timer(
            fire: Date(timeIntervalSinceNow: NSEvent.keyRepeatDelay),
            interval: NSEvent.keyRepeatInterval,
            repeats: true
        ) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.isActive(), self.session != nil, !self.isSuspended() else {
                self.stopMinimizedRepeat()
                return
            }
            self.onCycleMinimized?(self.repeatBackward)
        }
        minimizedRepeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMinimizedRepeat() {
        minimizedRepeatTimer?.invalidate()
        minimizedRepeatTimer = nil
    }

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
        source = src
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    var isInstalled: Bool { tap != nil }

    // Remove the tap from the event stream. An active tap that has lost
    // Accessibility can stall every keyboard and mouse event system-wide, so
    // it must come out as soon as the grant is gone.
    func uninstall() {
        stopMinimizedRepeat()
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        session = nil
        sessionReleaseOnShift = false
        fnWasDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stopMinimizedRepeat()
            // Re-enabling after Accessibility was revoked (e.g. `tccutil
            // reset`) loops disable/enable and freezes input system-wide.
            guard AXIsProcessTrusted() else {
                print("tap: Accessibility revoked; removing the event tap")
                uninstall()
                onTrustRevoked?()
                return Unmanaged.passUnretained(event)
            }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // A shortcut recorder is capturing keys; let them all through.
        if isSuspended() {
            stopMinimizedRepeat()
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let shift = flags.contains(.maskShift)
        let option = flags.contains(.maskAlternate)
        let control = flags.contains(.maskControl)
        let backward = shift
        repeatBackward = backward

        let activeNow = isActive()
        // A session ends through commit or cancel; clear the remembered shortcut
        // so the next press starts fresh.
        if !activeNow {
            stopMinimizedRepeat()
            session = nil
            sessionReleaseOnShift = false
        }

        if type == .keyDown {
            // Cycling: the trigger key again while its modifiers are still held.
            if activeNow, let session, keycode == session.keyCode {
                stopMinimizedRepeat()
                print("tap: cycle (backward=\(backward))")
                onCycle?(backward)
                return nil
            }
            if !activeNow {
                // macOS reports Fn through `.flagsChanged`, and the flag is often
                // missing from the keydown's own flags, so also consult the
                // state tracked from those events.
                let fn = flags.contains(.maskSecondaryFn) || fnWasDown
                // The trigger key cycles open windows; the trigger key plus Fn
                // cycles every window (open and minimized together).
                if primaryHotkey.matches(keycode, flags) {
                    session = primaryHotkey
                    sessionReleaseOnShift = primaryHotkey.commitModifiers.isEmpty
                    if fn {
                        print("tap: trigger all (fn) \(primaryHotkey.displayString)")
                        onTriggerAll?()
                    } else {
                        print("tap: trigger \(primaryHotkey.displayString)")
                        onTrigger?()
                    }
                    return nil
                }
                if overviewHotkey.matches(keycode, flags) {
                    session = overviewHotkey
                    sessionReleaseOnShift = overviewHotkey.commitModifiers.isEmpty
                    if fn {
                        print("tap: trigger overview all (fn) \(overviewHotkey.displayString)")
                        onTriggerOverviewAll?()
                    } else {
                        print("tap: trigger overview \(overviewHotkey.displayString)")
                        onTriggerOverview?()
                    }
                    return nil
                }
            }
            // While the overlay is up, `s` or `f` toggles between the
            // current-Space switcher and the all-Spaces overview, and back. Both
            // work with the trigger modifier still held (Cmd+S / Option+S), and
            // Cmd+F works explicitly regardless of which trigger opened it.
            if activeNow, keycode == kVK_S || keycode == kVK_F {
                let held = flags.intersection(Hotkey.relevantModifiers)
                let matchesSession = session.map { held == $0.normalizedModifiers } ?? false
                let explicitCommandF = keycode == kVK_F && held == .maskCommand
                if matchesSession || explicitCommandF {
                    print("tap: toggle spaces overview")
                    onToggleMode?()
                }
                return nil
            }
            // While the overlay is up, Cmd+1…9 switches straight to the Nth
            // active window of the current Space, without waiting for Cmd to be
            // released.
            if activeNow, flags.contains(.maskCommand), let number = kVK_Digits[keycode] {
                stopMinimizedRepeat()
                print("tap: switch to tile #\(number)")
                onSelectNumber?(number)
                return nil
            }
            if activeNow, keycode == kVK_Escape {
                stopMinimizedRepeat()
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
                        stopMinimizedRepeat()
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
            if !flags.contains(.maskSecondaryFn) { stopMinimizedRepeat() }
            let fn = flags.contains(.maskSecondaryFn)
            let fnPressed = keycode == kVK_Function && fn && !fnWasDown
            fnWasDown = fn
            guard activeNow, let session else { return Unmanaged.passUnretained(event) }
            // Fn steps through minimized windows while the switcher is open.
            if fnPressed, !sessionReleaseOnShift, !session.isReleased(flags) {
                print("tap: cycle minimized (fn)")
                onCycleMinimized?(backward)
                startMinimizedRepeat()
                return Unmanaged.passUnretained(event)
            }
            if session.isReleased(flags) || (sessionReleaseOnShift && !shift) {
                stopMinimizedRepeat()
                print("tap: commit (hotkey released, flags=\(flags.rawValue))")
                self.session = nil
                sessionReleaseOnShift = false
                onCommit?()
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
