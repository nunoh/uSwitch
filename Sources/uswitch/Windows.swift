import AppKit
import ApplicationServices

// Private HIServices call that returns the WindowServer id of an AX window.
// Unlike the AXWindowNumber attribute, it works for every app, Chrome included.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    let bounds: CGRect
    // Minimized windows are still listed (the enumeration uses `.optionAll`),
    // but render as a compact title strip instead of a live thumbnail.
    var isMinimized: Bool = false
    // False for windows on another Space (or otherwise not rendered). Their
    // live thumbnail can't be captured, so only a cached one is shown.
    var isOnScreen: Bool = true
    // Home Space for the all-Spaces overview. nil in the current-Space list.
    var spaceID: CGSSpaceID? = nil
    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
}

enum Windows {
    // AX does not expose a public Swift constant for this attribute, but it is
    // the WindowServer window number returned by CGWindowListCopyWindowInfo.
    // Matching by title is not sufficient: an app can have several untitled
    // windows, or several documents with the same title.
    private static let axWindowNumberAttribute = "AXWindowNumber" as CFString

    static func currentSpace(on screen: NSScreen?) -> [WindowInfo] {
        let descriptors = Spaces.orderedSpaces(for: screen)
        let current = descriptors.filter(\.isCurrent)
        let list = assemble(descriptors: current.isEmpty ? descriptors : current)
        print("[windows] currentSpace count=\(list.count)")
        for w in list {
            print("  - \(w.appName) [\(w.id)] minimized=\(w.isMinimized) spaces=\(Spaces.spaceIDs(for: w.id).sorted())")
        }
        return list
    }

    /// Every switchable window across all Spaces of the display the overlay
    /// opens on, tagged with its home Space. Ordering is front-to-back as
    /// reported by WindowServer.
    static func allSpaces(on screen: NSScreen?) -> [WindowInfo] {
        var descriptors = Spaces.orderedSpaces(for: screen)
        // Current Space first so sticky windows land there.
        if let idx = descriptors.firstIndex(where: { $0.isCurrent }) {
            descriptors.insert(descriptors.remove(at: idx), at: 0)
        }
        let list = assemble(descriptors: descriptors)
        print("[windows] allSpaces spaces=\(descriptors.map { "\($0.label)=\($0.id)" }) count=\(list.count)")
        return list
    }

    // Membership is decided by WindowServer's own per-Space window lists, not by
    // filtering `CGWindowListCopyWindowInfo(.optionAll)`. `.optionAll` keeps a
    // pile of leftover surfaces an app no longer reports (Calendar alone leaves
    // a dozen); the per-Space list does not. `candidates()` only supplies the
    // metadata (title, bounds, on-screen) for ids that survive.
    private static func assemble(descriptors: [Spaces.SpaceDescriptor]) -> [WindowInfo] {
        guard !descriptors.isEmpty else { return [] }
        var spaceFor: [CGWindowID: CGSSpaceID] = [:]
        for descriptor in descriptors {
            for id in Spaces.windowIDs(onSpace: descriptor.id) where spaceFor[id] == nil {
                spaceFor[id] = descriptor.id
            }
        }
        let all = candidates()
        let tagged: [WindowInfo]
        if spaceFor.isEmpty {
            // WindowServer's per-Space list came back empty (unexpected). Fall
            // back to matching each window's reported Space so the switcher
            // still works rather than showing nothing.
            print("[windows] per-Space lists unavailable; falling back to spaceIDs")
            tagged = all.compactMap { window -> WindowInfo? in
                let ids = Spaces.spaceIDs(for: window.id)
                guard let match = descriptors.first(where: { ids.contains($0.id) }) else { return nil }
                var tagged = window
                tagged.spaceID = match.id
                return tagged
            }
        } else {
            tagged = all.compactMap { window -> WindowInfo? in
                guard let space = spaceFor[window.id] else { return nil }
                var tagged = window
                tagged.spaceID = space
                return tagged
            }
        }
        return orderFrontToBack(tagged).pruningNonStandardWindows()
    }

    // `CGWindowListCopyWindowInfo(.optionAll)` does not preserve z-order — it can
    // list a minimized window ahead of the focused one — so the "previous
    // window" target has to come from `.optionOnScreenOnly`, which is guaranteed
    // front-to-back. Windows that are not on screen keep their relative order
    // after the on-screen ones.
    private static func orderFrontToBack(_ list: [WindowInfo]) -> [WindowInfo] {
        let ranks = onScreenRanks()
        return list.enumerated()
            .sorted { lhs, rhs in
                let l = ranks[lhs.element.id] ?? Int.max
                let r = ranks[rhs.element.id] ?? Int.max
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    private static func onScreenRanks() -> [CGWindowID: Int] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var ranks: [CGWindowID: Int] = [:]
        for (index, dict) in raw.enumerated() {
            if let id = dict[kCGWindowNumber as String] as? CGWindowID {
                ranks[id] = index
            }
        }
        return ranks
    }

    // Metadata for every layer-0 window. Uses `.optionAll` so minimized windows
    // and windows on other Spaces are included.
    private static func candidates() -> [WindowInfo] {
        let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { dict -> WindowInfo? in
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let id = dict[kCGWindowNumber as String] as? CGWindowID,
                  let appName = dict[kCGWindowOwnerName as String] as? String,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            guard bounds.width > 50, bounds.height > 50 else { return nil }
            // Fully transparent windows are ghosts; skip them.
            if let alpha = dict[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { return nil }
            guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            // Agent apps (no Dock tile) are absent from the system switcher, so
            // their helper windows must not appear here either. Hidden apps are
            // likewise absent — `.optionAll` would otherwise surface them.
            guard app.activationPolicy == .regular, !app.isHidden else { return nil }
            let title = (dict[kCGWindowName as String] as? String) ?? ""
            let onScreen = (dict[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
            return WindowInfo(
                id: id,
                pid: pid,
                title: title,
                appName: appName,
                bounds: bounds,
                isOnScreen: onScreen
            )
        }
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

        // A minimized window must be restored before it can be focused; while
        // it sits in the Dock, kAXMain and the raise action are no-ops.
        if window.isMinimized {
            let result = AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            print("raise: unminimized window id=\(window.id) (result=\(result.rawValue))")
        }

        // Activating an app that is already frontmost does not select one of
        // its other windows. Make the specific AX window main and focused, then
        // raise it so switching within the same app is deterministic as well.
        // Chrome ignores AXFocusedWindow on the app unless the window is main.
        let mainResult = AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)
        let focusResult = AXUIElementSetAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            axWin
        )
        let raiseResult = AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
        print(
            "raise: focused and raised window id=\(window.id) " +
            "(main=\(mainResult.rawValue), focus=\(focusResult.rawValue), raise=\(raiseResult.rawValue))"
        )
    }

    // Quit the whole application that owns the window — the same request
    // Cmd+Q makes, without activating the app first. Returns whether the quit
    // request was delivered (not whether the app actually exited).
    static func quit(_ window: WindowInfo) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else {
            print("quit: no running app for pid \(window.pid)")
            return false
        }
        let ok = app.terminate()
        print("quit: terminate \(app.localizedName ?? "?") = \(ok)")
        return ok
    }

    // Close a single window by pressing its accessibility close button. Doing
    // it through AX leaves the frontmost app and the uSwitch overlay untouched,
    // unlike sending Cmd+W, which only the active app would handle.
    static func close(_ window: WindowInfo) -> Bool {
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let axWindows = ref as? [AXUIElement],
              let axWin = matchingAXWindow(for: window, in: axWindows)
        else {
            print("close: no AX window matching WindowServer id \(window.id)")
            return false
        }
        var buttonRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWin, kAXCloseButtonAttribute as CFString, &buttonRef) == .success,
              let button = buttonRef,
              CFGetTypeID(button) == AXUIElementGetTypeID()
        else {
            print("close: window id \(window.id) exposes no AX close button")
            return false
        }
        let result = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        print("close: pressed close button for window id \(window.id) (result=\(result.rawValue))")
        return result == .success
    }

    // Minimize a single window through AX, leaving the frontmost app and the
    // uSwitch overlay where they are.
    static func minimize(_ window: WindowInfo) -> Bool {
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let axWindows = ref as? [AXUIElement],
              let axWin = matchingAXWindow(for: window, in: axWindows)
        else {
            print("minimize: no AX window matching WindowServer id \(window.id)")
            return false
        }
        var buttonRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWin, kAXMinimizeButtonAttribute as CFString, &buttonRef) == .success,
           let button = buttonRef,
           CFGetTypeID(button) == AXUIElementGetTypeID() {
            let result = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            print("minimize: pressed minimize button for window id \(window.id) (result=\(result.rawValue))")
            return result == .success
        }
        // Apps without a minimize button (or a proxy button) still honour the
        // attribute directly.
        let result = AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        print("minimize: set AXMinimized for window id \(window.id) (result=\(result.rawValue))")
        return result == .success
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
    // them as a window at all, and the system switcher skips them. The same
    // accessibility round trip tells us whether the window is minimized, so the
    // two are classified together.
    fileprivate static func classify(
        _ window: WindowInfo,
        in axWindows: Windows.AXWindowList
    ) -> (standard: Bool, minimized: Bool) {
        switch axWindows {
        case .unavailable:
            // No accessibility answer: keep the window. Space membership has
            // already vouched for it, and its minimized state is unknown.
            return (true, false)
        case .available(let list):
            let matches = list.filter { axMatches($0, window) }
            guard !matches.isEmpty else {
                // The app did not report this window. Accessibility only
                // exposes windows on the active Space, so this is a window on
                // another Space, not a fake one. Keep it, minimized unknown.
                return (true, false)
            }
            guard matches.contains(where: { subrole(for: $0).map(switchableSubroles.contains) ?? true })
            else { return (false, false) }
            let minimized = matches.contains(where: isMinimized)
            return (true, minimized)
        }
    }

    private static func isMinimized(_ axWin: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString, &ref) == .success,
              let number = ref as? NSNumber
        else { return false }
        return number.boolValue
    }

    // Distinguishes "the app answered and has no windows" (a WindowServer
    // leftover, not a real window) from "the app did not answer at all" (keep
    // its windows rather than hide a real one from a busy app).
    enum AXWindowList {
        case unavailable
        case available([AXUIElement])
    }

    static func axWindowList(for pid: pid_t) -> AXWindowList {
        let app = AXUIElementCreateApplication(pid)
        // The switcher must open at once; do not block on a hung app.
        AXUIElementSetMessagingTimeout(app, 0.25)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let axWindows = ref as? [AXUIElement]
        else { return .unavailable }
        return .available(axWindows)
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
        var windowID: CGWindowID = 0
        if _AXUIElementGetWindow(axWin, &windowID) == .success, windowID != 0 {
            return windowID
        }
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
        var axWindowsByPID: [pid_t: Windows.AXWindowList] = [:]
        return compactMap { window in
            let axWindows = axWindowsByPID[window.pid] ?? {
                let fetched = Windows.axWindowList(for: window.pid)
                axWindowsByPID[window.pid] = fetched
                return fetched
            }()
            let verdict = Windows.classify(window, in: axWindows)
            guard verdict.standard else { return nil }
            var pruned = window
            pruned.isMinimized = verdict.minimized
            return pruned
        }
    }
}
