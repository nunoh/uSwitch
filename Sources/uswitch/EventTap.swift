import AppKit
import CoreGraphics

private let kVK_Tab: CGKeyCode = 48
private let kVK_Escape: CGKeyCode = 53
private let kVK_Q: CGKeyCode = 12
private let kVK_W: CGKeyCode = 13
private let kVK_M: CGKeyCode = 46

final class EventTap {
    var onTrigger: (() -> Void)?
    var onCycle: ((Bool) -> Void)?  // backward = true
    var onEscape: (() -> Void)?
    var onCommit: (() -> Void)?
    var onQuit: (() -> Void)?
    var onCloseWindow: (() -> Void)?
    var onMinimize: (() -> Void)?
    var isActive: () -> Bool = { false }

    private var tap: CFMachPort?

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

        let flags = event.flags
        let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let cmd = flags.contains(.maskCommand)
        let shift = flags.contains(.maskShift)
        let option = flags.contains(.maskAlternate)
        let control = flags.contains(.maskControl)

        if type == .keyDown {
            if keycode == kVK_Tab, cmd {
                if isActive() {
                    print("tap: cycle (shift=\(shift))")
                    onCycle?(shift)
                } else {
                    print("tap: trigger")
                    onTrigger?()
                }
                return nil
            }
            if isActive(), keycode == kVK_Escape {
                print("tap: escape")
                onEscape?()
                return nil
            }
            // While the overlay is up, Cmd+Q / Cmd+W / Cmd+M act on the selected
            // tile instead of the frontmost app. Swallow them even with extra
            // modifiers (Cmd+Shift+Q is logout) so nothing leaks through.
            if isActive(), cmd, (keycode == kVK_Q || keycode == kVK_W || keycode == kVK_M) {
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
                    default:
                        print("tap: minimize selected window")
                        onMinimize?()
                    }
                }
                return nil
            }
        } else if type == .flagsChanged {
            if isActive(), !cmd {
                print("tap: commit (cmd released, flags=\(flags.rawValue))")
                onCommit?()
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
