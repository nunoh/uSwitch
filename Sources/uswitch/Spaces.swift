import AppKit
import CoreGraphics
import Foundation

// SkyLight private API. Other switchers (AltTab, HyperSwitch) rely on this to
// answer "which Space is this window on?" — public CG APIs can't tell us, and
// CGWindowListCopyWindowInfo reports windows from *both* Spaces during a
// Space-switch animation.

typealias CGSConnectionID = Int32
typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ windowIDs: CFArray) -> CFArray?

private let kCGSAllSpacesMask: Int32 = 7

enum Spaces {
    nonisolated(unsafe) private static var cachedActiveSpaceIDs: Set<CGSSpaceID> = []
    nonisolated(unsafe) private static var didStartObserving = false

    /// Subscribe to active-Space changes as a cache warmer. The notification is
    /// not reliable on its own — macOS sometimes drops it, leaving the cache
    /// pinned to a stale Space until the app restarts. Treat it as a hint; the
    /// authoritative answer comes from a live read at trigger time.
    static func startObserving() {
        guard !didStartObserving else { return }
        didStartObserving = true
        cachedActiveSpaceIDs = readCurrentSpaceIDs()
        print("[spaces] startObserving — initial cache=\(cachedActiveSpaceIDs)")
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let new = readCurrentSpaceIDs()
            print("[spaces] activeSpaceDidChange fired — was=\(cachedActiveSpaceIDs) now=\(new)")
            cachedActiveSpaceIDs = new
        }
    }

    private static func readCurrentSpaceIDs() -> Set<CGSSpaceID> {
        let cid = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return [] }
        return Set(displays.compactMap(currentSpaceID))
    }

    /// The "Current Space" ID from one entry of the managed-displays array.
    private static func currentSpaceID(of display: [String: Any]) -> CGSSpaceID? {
        guard let current = display["Current Space"] as? [String: Any] else { return nil }
        return current["ManagedSpaceID"] as? CGSSpaceID ?? current["id64"] as? CGSSpaceID
    }

    /// Trusted "current Space" IDs. Always re-reads at the call site —
    /// activeSpaceDidChange can be silently dropped by macOS, which would
    /// otherwise leave the cache pinned to a previous Space and make the
    /// switcher show no windows after a Space switch. The live read also
    /// refreshes the cache so it stays warm.
    static func reportedCurrentSpaceIDs() -> Set<CGSSpaceID> {
        let live = readCurrentSpaceIDs()
        if !live.isEmpty {
            if live != cachedActiveSpaceIDs {
                print("[spaces] live read corrected cache — was=\(cachedActiveSpaceIDs) now=\(live)")
                cachedActiveSpaceIDs = live
            }
            return live
        }
        return cachedActiveSpaceIDs
    }

    /// All Space IDs the given window belongs to (sticky windows belong to
    /// every Space).
    static func spaceIDs(for windowID: CGWindowID) -> Set<CGSSpaceID> {
        let cid = CGSMainConnectionID()
        let arr = [windowID] as CFArray
        guard let raw = CGSCopySpacesForWindows(cid, kCGSAllSpacesMask, arr) as? [NSNumber] else { return [] }
        return Set(raw.map { $0.uint64Value })
    }

    /// Current-Space IDs to filter the switcher by: only the Space of the
    /// display the overlay is showing on, so windows living on another
    /// monitor's current Space don't leak into the list. Falls back to every
    /// display's current Space when the display can't be matched (single
    /// display, or a read that turns up nothing).
    static func currentSpaceIDs(for screen: NSScreen?) -> Set<CGSSpaceID> {
        if let screen, let ids = liveSpaceIDs(for: screen), !ids.isEmpty {
            print("[spaces] scoped to display \(displayIdentifier(for: screen) ?? "?") space=\(ids)")
            return ids
        }
        let all = reportedCurrentSpaceIDs()
        print("[spaces] no display match — falling back to all displays \(all)")
        return all
    }

    /// The current Space of a single display, matched by its CoreGraphics UUID
    /// against the "Display Identifier" key. nil when the display isn't found.
    private static func liveSpaceIDs(for screen: NSScreen) -> Set<CGSSpaceID>? {
        guard let wantID = displayIdentifier(for: screen) else { return nil }
        let cid = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return nil }
        for display in displays where (display["Display Identifier"] as? String) == wantID {
            if let id = currentSpaceID(of: display) { return [id] }
        }
        return nil
    }

    /// CoreGraphics display-UUID string for a screen, matching the
    /// "Display Identifier" values in CGSCopyManagedDisplaySpaces.
    private static func displayIdentifier(for screen: NSScreen) -> String? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(num.uint32Value))?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
