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
    static func currentSpace() -> [WindowInfo] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { dict in
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let id = dict[kCGWindowNumber as String] as? CGWindowID,
                  let appName = dict[kCGWindowOwnerName as String] as? String,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            guard bounds.width > 50, bounds.height > 50 else { return nil }
            let title = (dict[kCGWindowName as String] as? String) ?? ""
            return WindowInfo(id: id, pid: pid, title: title, appName: appName, bounds: bounds)
        }
    }

    static func raise(_ window: WindowInfo) {
        guard let target = NSRunningApplication(processIdentifier: window.pid) else {
            print("raise: no running app for pid \(window.pid)")
            return
        }
        let from = NSWorkspace.shared.frontmostApplication ?? target
        let ok: Bool
        if #available(macOS 14.0, *) {
            ok = target.activate(from: from)
        } else {
            ok = target.activate(options: [.activateIgnoringOtherApps])
        }
        print("raise: activate=\(ok) from=\(from.localizedName ?? "?") -> \(target.localizedName ?? "?")")

        let app = AXUIElementCreateApplication(window.pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let axWindows = ref as? [AXUIElement] else { return }
        for axWin in axWindows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
            if let t = titleRef as? String, t == window.title {
                AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
                return
            }
        }
    }
}
