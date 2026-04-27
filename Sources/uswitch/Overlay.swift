import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = true
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private let tileWidth: CGFloat = 180
private let tileHeight: CGFloat = 120
private let iconSize: CGFloat = 56

struct ThumbnailTile: View {
    let window: WindowInfo
    let thumbnail: NSImage?
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.25))

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(width: tileWidth - 8, height: tileHeight - 8)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if let icon = window.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .shadow(radius: 2)
                }
            }
            .frame(width: tileWidth, height: tileHeight)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.white.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2.5)
            )

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: tileWidth)
        }
    }

    private var label: String {
        window.title.isEmpty ? window.appName : window.title
    }
}

struct OverlayView: View {
    let windows: [WindowInfo]
    let thumbnails: [CGWindowID: NSImage]
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(windows.enumerated()), id: \.element.id) { idx, w in
                ThumbnailTile(
                    window: w,
                    thumbnail: thumbnails[w.id],
                    selected: idx == selectedIndex
                )
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

@MainActor
final class Switcher {
    private let panel = OverlayPanel()
    private var hosting: NSHostingView<OverlayView>?
    private var windows: [WindowInfo] = []
    private var thumbnails: [CGWindowID: NSImage] = [:]
    private var selectedIndex: Int = 0
    private var openGeneration: Int = 0
    private let cache: ThumbnailCache
    var isOpen: Bool { panel.isVisible }

    init(cache: ThumbnailCache) {
        self.cache = cache
    }

    func open() {
        let t0 = Date()
        windows = Windows.currentSpace()
        guard !windows.isEmpty else { return }
        selectedIndex = windows.count > 1 ? 1 : 0
        thumbnails = Dictionary(uniqueKeysWithValues: windows.compactMap { w in
            cache.image(for: w.id).map { (w.id, $0) }
        })
        render()
        positionAndShow()
        print("panel shown in \(Int(Date().timeIntervalSince(t0) * 1000))ms (cached \(thumbnails.count)/\(windows.count))")

        // Fall back to one-shot capture for windows we've never seen.
        let missing = windows.filter { thumbnails[$0.id] == nil }
        guard !missing.isEmpty else { return }
        openGeneration &+= 1
        let myGen = openGeneration
        let ids = missing.map { $0.id }
        Task.detached(priority: .userInitiated) { [weak self] in
            for id in ids {
                if let img = Capture.snapshot(of: id) {
                    await self?.applyMissing(img, for: id, generation: myGen)
                }
            }
        }
    }

    private func applyMissing(_ img: NSImage, for id: CGWindowID, generation: Int) {
        guard openGeneration == generation, isOpen else { return }
        thumbnails[id] = img
        cache.store(img, for: id)
        render()
    }

    func cycle(backward: Bool) {
        guard !windows.isEmpty else { return }
        let n = windows.count
        selectedIndex = backward ? (selectedIndex - 1 + n) % n : (selectedIndex + 1) % n
        render()
    }

    func commit() {
        guard isOpen else { print("commit: not open, ignoring"); return }
        let target = windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
        close()
        if let target {
            print("commit: raising [\(target.pid)] \(target.appName) — \(target.title)")
            Windows.raise(target)
        } else {
            print("commit: no target at index \(selectedIndex) (windows.count=\(windows.count))")
        }
    }

    func close() {
        panel.orderOut(nil)
    }

    private func render() {
        let view = OverlayView(windows: windows, thumbnails: thumbnails, selectedIndex: selectedIndex)
        if let hosting {
            hosting.rootView = view
        } else {
            let h = NSHostingView(rootView: view)
            hosting = h
            panel.contentView = h
        }
        if let hosting {
            panel.setContentSize(hosting.fittingSize)
        }
    }

    private func positionAndShow() {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }
}
