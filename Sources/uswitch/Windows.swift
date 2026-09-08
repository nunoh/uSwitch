import AppKit
import ApplicationServices

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    let bounds: CGRect
    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
}

enum Windows {
    // AX does not expose a public Swift constant for this attribute, but it is
    // the WindowServer window number returned by CGWindowListCopyWindowInfo.
    // Matching by title is not sufficient: an app can have several untitled
    // windows, or several documents with the same title.
    private static let axWindowNumberAttribute = "AXWindowNumber" as CFString

    static func currentSpace(on screen: NSScreen?) -> [WindowInfo] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let candidates: [WindowInfo] = raw.compactMap { dict in
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let id = dict[kCGWindowNumber as String] as? CGWindowID,
                  let appName = dict[kCGWindowOwnerName as String] as? String,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            guard bounds.width > 50, bounds.height > 50 else { return nil }
            // Agent apps (no Dock tile) are absent from the system switcher, so
            // their helper windows must not appear here either.
            guard NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            else { return nil }
            let title = (dict[kCGWindowName as String] as? String) ?? ""
            return WindowInfo(id: id, pid: pid, title: title, appName: appName, bounds: bounds)
        }
        .pruningNonStandardWindows()
        // CGWindowList reports windows across every display, plus stale ones
        // during/after a Space switch. Filter to windows on the current Space
        // of the display the overlay opened on (sticky/all-Spaces windows
        // belong to every Space, so they're kept too).
        let destination = Spaces.currentSpaceIDs(for: screen)
        print("[windows] currentSpace destination=\(destination) candidates=\(candidates.count)")
        for w in candidates {
            print("  - \(w.appName) [\(w.id)] spaces=\(Spaces.spaceIDs(for: w.id))")
        }
        guard !destination.isEmpty else { return candidates }
        return candidates.filter { !Spaces.spaceIDs(for: $0.id).isDisjoint(with: destination) }
    }

    static func raise(_ window: WindowInfo) {
        guard let target = NSRunningApplication(processIdentifier: window.pid) else {
            print("raise: no running app for pid \(window.pid)")
            return
        }
        let from = NSWorkspace.shared.frontmostApplication ?? target
        var ok: Bool
        if #available(macOS 14.0, *) {
            ok = target.activate(from: from)
        } else {
            ok = target.activate(options: [.activateIgnoringOtherApps])
        }
        // macOS 14+ activate(from:) needs the source app to yield; some apps
        // (Ghostty, Electron, etc.) don't, so it returns false silently.
        // Fall back to the legacy path and force AXFrontmost.
        if !ok {
            ok = target.activate(options: [.activateIgnoringOtherApps])
            let axApp = AXUIElementCreateApplication(window.pid)
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            print("raise: fallback activate=\(ok) (AXFrontmost forced)")
        }
        print("raise: activate=\(ok) from=\(from.localizedName ?? "?") -> \(target.localizedName ?? "?")")

        let app = AXUIElementCreateApplication(window.pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let axWindows = ref as? [AXUIElement] else { return }
        let axWin = matchingAXWindow(for: window, in: axWindows)

        guard let axWin else {
            print("raise: could not find AX window matching WindowServer id \(window.id)")
            return
        }

        // Activating an app that is already frontmost does not select one of
        // its other windows. Focus the specific AX window first, then raise it
        // so switching within the same app is deterministic as well.
        let focusResult = AXUIElementSetAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            axWin
        )
        let raiseResult = AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
        print(
            "raise: focused and raised window id=\(window.id) " +
            "(focus=\(focusResult.rawValue), raise=\(raiseResult.rawValue))"
        )
    }

    // Subroles a real, switchable window can report. Electron and Tauri apps
    // often label their main window AXDialog, so the list cannot be narrowed
    // to AXStandardWindow alone. It does exclude AXUnknown and the floating
    // subroles used by panels and heads-up overlays.
    private static let switchableSubroles: Set<String> = [
        kAXStandardWindowSubrole as String,
        kAXDialogSubrole as String,
    ]

    // A layer-0 window is not necessarily switchable. Floating panels and
    // overlays (ChatGPT's "Computer Use" controls, for example) look like
    // ordinary windows to CGWindowList, but the owning app does not publish
    // them as a window at all, and the system switcher skips them.
    fileprivate static func isStandardWindow(_ window: WindowInfo, in axWindows: [AXUIElement]?) -> Bool {
        // No usable accessibility answer: keep the window rather than hide a
        // real one from an app that is busy or does not respond to AX.
        guard let axWindows else { return true }
        let matches = axWindows.filter { axMatches($0, window) }
        guard !matches.isEmpty else { return false }
        return matches.contains { subrole(for: $0).map(switchableSubroles.contains) ?? true }
    }

    fileprivate static func axWindows(for pid: pid_t) -> [AXUIElement]? {
        let app = AXUIElementCreateApplication(pid)
        // The switcher must open at once; do not block on a hung app.
        AXUIElementSetMessagingTimeout(app, 0.25)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let axWindows = ref as? [AXUIElement],
              !axWindows.isEmpty
        else { return nil }
        return axWindows
    }

    private static func axMatches(_ axWin: AXUIElement, _ window: WindowInfo) -> Bool {
        if let number = windowNumber(for: axWin) { return number == window.id }
        return framesMatch(frame(for: axWin), window.bounds)
    }

    private static func subrole(for axWin: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWin, kAXSubroleAttribute as CFString, &ref) == .success
        else { return nil }
        return ref as? String
    }

    private static func windowNumber(for axWin: AXUIElement) -> CGWindowID? {
        var numberRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWin, axWindowNumberAttribute, &numberRef) == .success,
           let number = numberRef as? NSNumber {
            return number.uint32Value
        }
        return nil
    }

    private static func title(for axWin: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }

    private static func matchingAXWindow(
        for window: WindowInfo,
        in axWindows: [AXUIElement]
    ) -> AXUIElement? {
        // This is the only direct identity link provided by some apps.
        if let exact = axWindows.first(where: { windowNumber(for: $0) == window.id }) {
            return exact
        }

        // Finder does not reliably surface AXWindowNumber. Its AX frames do
        // correspond to the WindowServer frame, however, and remain distinct
        // when several Finder windows share an empty or duplicate title.
        let framedMatches = axWindows.filter { framesMatch(frame(for: $0), window.bounds) }
        if framedMatches.count == 1 {
            return framedMatches[0]
        }

        // Last resort for apps whose AX frame is unavailable or rounded. A
        // unique title is still a useful identifier, but never guess between
        // duplicate titles.
        let titleMatches = axWindows.filter { title(for: $0) == window.title }
        return window.title.isEmpty || titleMatches.count != 1 ? nil : titleMatches[0]
    }

    private static func frame(for axWin: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef,
              let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func framesMatch(_ lhs: CGRect?, _ rhs: CGRect) -> Bool {
        guard let lhs else { return false }
        // WindowServer shadows and accessibility frames can differ by a few
        // pixels, especially while a window is being resized.
        let tolerance: CGFloat = 12
        return abs(lhs.minX - rhs.minX) <= tolerance &&
            abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }
}

private extension Array where Element == WindowInfo {
    // One accessibility round trip per app, not per window.
    func pruningNonStandardWindows() -> [WindowInfo] {
        var axWindowsByPID: [pid_t: [AXUIElement]?] = [:]
        return filter { window in
            let axWindows = axWindowsByPID[window.pid] ?? {
                let fetched = Windows.axWindows(for: window.pid)
                axWindowsByPID[window.pid] = fetched
                return fetched
            }()
            return Windows.isStandardWindow(window, in: axWindows)
        }
    }
}
