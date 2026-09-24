import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

// Temporary diagnostic: dumps what the switcher actually sees, so ghost windows
// and Space-assignment bugs can be told apart from guesses. Run with:
//   dist/uswitch.app/Contents/MacOS/uswitch --diagnose
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum Diagnose {
    static func run() {
        print("accessibilityTrusted=\(AXIsProcessTrusted())")

        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        print("\n=== running regular apps (\(apps.count)) ===")
        for app in apps {
            print("pid=\(app.processIdentifier) name=\(app.localizedName ?? "?") hidden=\(app.isHidden) terminated=\(app.isTerminated)")
        }

        print("\n=== spaces ===")
        for screen in NSScreen.screens {
            print("screen=\(screen.localizedName) orderedSpaces=\(Spaces.orderedSpaces(for: screen).map { "\($0.label)#\($0.id)\($0.isCurrent ? "*" : "")" })")
        }
        print("reportedCurrentSpaceIDs=\(Spaces.reportedCurrentSpaceIDs())")

        print("\n=== CGWindowList .optionAll (layer 0) ===")
        let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return }
        var rows: [(id: CGWindowID, pid: pid_t, app: String)] = []
        for dict in raw {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let id = dict[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            let name = dict[kCGWindowOwnerName as String] as? String ?? "?"
            let title = dict[kCGWindowName as String] as? String ?? ""
            let onScreen = (dict[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            let alpha = (dict[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? -1
            let store = (dict[kCGWindowStoreType as String] as? NSNumber)?.intValue ?? -1
            let sharing = (dict[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? -1
            let spaceIDs = Spaces.spaceIDs(for: id)
            let running = NSRunningApplication(processIdentifier: pid) != nil
            print("id=\(id) pid=\(pid) app=\(name) running=\(running) onScreen=\(onScreen) store=\(store) sharing=\(sharing) alpha=\(alpha) spaces=\(spaceIDs.sorted()) title=\(title.prefix(40))")
            rows.append((id, pid, name))
        }

        print("\n=== AX windows per running regular app ===")
        var axNumbers = Set<CGWindowID>()
        for app in apps {
            switch Windows.axWindowList(for: app.processIdentifier) {
            case .unavailable:
                print("\(app.localizedName ?? "?") pid=\(app.processIdentifier) axWindows=unavailable")
            case .available(let ax):
                print("\(app.localizedName ?? "?") pid=\(app.processIdentifier) axWindows=\(ax.count)")
                for (i, w) in ax.enumerated() {
                    var wid: CGWindowID = 0
                    let ok = _AXUIElementGetWindow(w, &wid)
                    if ok == .success { axNumbers.insert(wid) }
                    var minRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minRef)
                    let minimized = (minRef as? NSNumber)?.boolValue ?? false
                    print("   [\(i)] win=\(ok == .success ? String(wid) : "?") minimized=\(minimized)")
                }
            }
        }

        print("\n=== CG windows NOT backed by any AX window (ghosts) ===")
        for row in rows where !axNumbers.contains(row.id) {
            print("id=\(row.id) pid=\(row.pid) app=\(row.app)")
        }

        print("\n=== currentSpace() result ===")
        let current = Windows.currentSpace(on: nil)
        print("count=\(current.count)")
        for w in current {
            print("  \(w.appName) [\(w.id)] minimized=\(w.isMinimized) onScreen=\(w.isOnScreen) spaces=\(Spaces.spaceIDs(for: w.id).sorted())")
        }

        print("\n=== allSpaces() grouping ===")
        let all = Windows.allSpaces(on: nil)
        let grouped = Dictionary(grouping: all, by: { $0.spaceID })
        for (space, ws) in grouped.sorted(by: { String(describing: $0.key) < String(describing: $1.key) }) {
            print("space=\(space.map(String.init) ?? "nil"): \(ws.map { "\($0.appName)[\($0.id)]\($0.isMinimized ? " MIN" : "")" })")
        }
        print("allSpaces total=\(all.count) assigned=\(all.filter { $0.spaceID != nil }.count)")

        print("\n=== per-Space window list (CGSCopyWindowsWithOptionsAndTags, options=7) ===")
        for s in Spaces.orderedSpaces(for: nil) {
            let ids = Spaces.windowIDs(onSpace: s.id)
            let described = ids.sorted().map { id -> String in
                let app = raw.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == id })
                let name = app?[kCGWindowOwnerName as String] as? String ?? "?"
                let title = app?[kCGWindowName as String] as? String ?? ""
                return "\(id):\(name):\(title.prefix(20))"
            }
            print("space=\(s.label)#\(s.id) count=\(ids.count) \(described)")
        }

        print("\n=== SCShareableContent (all, onScreenWindowsOnly=false) ===")
        final class Box: @unchecked Sendable { var lines: [String] = [] }
        let box = Box()
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                box.lines.append("windows=\(content.windows.count)")
                for w in content.windows {
                    box.lines.append("id=\(w.windowID) app=\(w.owningApplication?.applicationName ?? "?") pid=\(w.owningApplication?.processID ?? -1) onScreen=\(w.isOnScreen) layer=\(w.windowLayer) title=\(w.title ?? "")")
                }
            } catch {
                box.lines.append("error=\(error)")
            }
            sem.signal()
        }
        while sem.wait(timeout: .now()) == .timedOut {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        box.lines.forEach { print($0) }
    }
}
