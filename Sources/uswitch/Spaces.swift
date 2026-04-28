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

    /// Subscribe to active-Space changes. macOS posts the notification the
    /// moment a new Space is committed (at the start of the slide animation,
    /// not the end), so the cache stays accurate even under rapid ctrl+arrow
    /// switching where CGSCopyManagedDisplaySpaces lags behind.
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
        var ids: Set<CGSSpaceID> = []
        for display in displays {
            if let current = display["Current Space"] as? [String: Any],
               let id = current["ManagedSpaceID"] as? CGSSpaceID ?? current["id64"] as? CGSSpaceID {
                ids.insert(id)
            }
        }
        return ids
    }

    /// Trusted "current Space" IDs. Prefers the cache updated on each
    /// activeSpaceDidChange notification; falls back to a live read before
    /// the first notification fires.
    static func reportedCurrentSpaceIDs() -> Set<CGSSpaceID> {
        cachedActiveSpaceIDs.isEmpty ? readCurrentSpaceIDs() : cachedActiveSpaceIDs
    }

    /// All Space IDs the given window belongs to (sticky windows belong to
    /// every Space).
    static func spaceIDs(for windowID: CGWindowID) -> Set<CGSSpaceID> {
        let cid = CGSMainConnectionID()
        let arr = [windowID] as CFArray
        guard let raw = CGSCopySpacesForWindows(cid, kCGSAllSpacesMask, arr) as? [NSNumber] else { return [] }
        return Set(raw.map { $0.uint64Value })
    }

    /// The Space the user is heading toward — just the cached active Space
    /// IDs, kept fresh by the activeSpaceDidChange observer.
    static func destinationSpaceIDs() -> Set<CGSSpaceID> {
        reportedCurrentSpaceIDs()
    }
}
