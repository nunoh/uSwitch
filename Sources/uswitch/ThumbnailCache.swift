import AppKit

@MainActor
final class ThumbnailCache {
    private var cache: [CGWindowID: NSImage] = [:]

    func image(for id: CGWindowID) -> NSImage? { cache[id] }

    func store(_ img: NSImage, for id: CGWindowID) { cache[id] = img }

    func startObserving() {
        let nc = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ]
        for name in names {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }
                MainActor.assumeIsolated {
                    self.scheduleRefresh(forPID: app.processIdentifier)
                }
            }
        }
    }

    private func scheduleRefresh(forPID pid: pid_t) {
        let ids = visibleWindowIDs(forPID: pid)
        guard !ids.isEmpty else { return }
        Task.detached(priority: .background) { [weak self] in
            // Brief wait so the activating/deactivating app has had a chance to paint
            // its current state before we snapshot it.
            try? await Task.sleep(nanoseconds: 100_000_000)
            for id in ids {
                if let img = Capture.snapshot(of: id) {
                    await self?.store(img, for: id)
                }
            }
        }
    }

    private func visibleWindowIDs(forPID pid: pid_t) -> [CGWindowID] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { dict in
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let owner = dict[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let id = dict[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 50, bounds.height > 50
            else { return nil }
            return id
        }
    }
}
