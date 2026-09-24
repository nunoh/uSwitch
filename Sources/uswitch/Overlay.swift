import AppKit
import QuartzCore
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
        collectionBehavior = overlayCollectionBehavior
        ignoresMouseEvents = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private let tileWidth: CGFloat = 180
private let tileHeight: CGFloat = 120
private let iconSize: CGFloat = 56
private let tileSpacing: CGFloat = 12
private let overlayPadding: CGFloat = 20
private let screenMargin: CGFloat = 80
private let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
    .moveToActiveSpace,
    .transient,
    .stationary,
    .ignoresCycle,
    .fullScreenAuxiliary,
]

// Grace period before the panel becomes visible. A fast Cmd+Tab flick
// (tap Tab, release Cmd within this window) switches to the previous window
// without ever flashing the UI.
private let panelShowDelay: TimeInterval = 0.1

// How long a tile takes to leave the overlay after quit / close / minimize.
// Short on purpose: a gentle fade and shrink, not a production.
private let tileRemovalDuration: TimeInterval = 0.16

struct ThumbnailTile: View {
    let window: WindowInfo
    let thumbnail: NSImage?
    let selected: Bool
    let hovered: Bool

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
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(strokeColor, lineWidth: selected ? 2.5 : 1.5)
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

    private var fillColor: Color {
        if selected { return Color.white.opacity(0.18) }
        if hovered { return Color.white.opacity(0.10) }
        return .clear
    }

    private var strokeColor: Color {
        if selected { return .accentColor }
        if hovered { return Color.white.opacity(0.5) }
        return .clear
    }
}

// The panel never becomes key, so every click arrives as a "first mouse";
// without this override SwiftUI tap gestures inside the panel are dropped.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct OverlayView: View {
    let windows: [WindowInfo]
    let thumbnails: [CGWindowID: NSImage]
    let selectedIndex: Int
    let hoveredIndex: Int?
    let maxTilesPerRow: Int
    let onSelect: (Int) -> Void
    let onHover: (Int) -> Void
    let onHoverEnd: (Int) -> Void

    var body: some View {
        Group {
            if windows.isEmpty {
                Color.clear.frame(width: tileWidth * 0.25, height: tileHeight * 0.25)
            } else {
                let rows = chunked(Array(windows.enumerated()), size: max(1, maxTilesPerRow))
                VStack(spacing: tileSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: tileSpacing) {
                            ForEach(row, id: \.element.id) { idx, w in
                                ThumbnailTile(
                                    window: w,
                                    thumbnail: thumbnails[w.id],
                                    selected: idx == selectedIndex,
                                    hovered: idx == hoveredIndex
                                )
                                .transition(
                                    .scale(scale: 0.85).combined(with: .opacity)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(idx) }
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active: onHover(idx)
                                    case .ended: onHoverEnd(idx)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(overlayPadding)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func chunked<T>(_ array: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [array] }
        return stride(from: 0, to: array.count, by: size).map {
            Array(array[$0..<min($0 + size, array.count)])
        }
    }
}

@MainActor
final class Switcher {
    private let panel = OverlayPanel()
    private var hosting: NSHostingView<OverlayView>?
    private var windows: [WindowInfo] = []
    private var thumbnails: [CGWindowID: NSImage] = [:]
    private var selectedIndex: Int = 0
    private var hoveredIndex: Int?
    private var openGeneration: Int = 0
    private var openScreen: NSScreen?
    private var openSpaceIDs: Set<CGSSpaceID> = []
    private var openTilesPerRow: Int = 1
    private var openMouseLocation: CGPoint = .zero
    private var hoverArmed = false
    private var activeSpaceObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var active = false
    private let cache: ThumbnailCache
    var isOpen: Bool {
        guard active else { return false }
        guard isStillInOpeningSpace() else {
            print("switcher: active Space no longer matches; clearing stale overlay state")
            close()
            return false
        }
        return true
    }

    init(cache: ThumbnailCache) {
        self.cache = cache
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleActiveSpaceDidChange()
            }
        }
        // A quit is asynchronous — the app may take a moment to exit. Refresh
        // when it actually goes away so the overlay drops its tiles right then.
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                self.refreshWindows()
            }
        }
    }

    deinit {
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    func open() {
        let t0 = Date()
        active = true
        openScreen = currentScreen()
        openSpaceIDs = Spaces.currentSpaceIDs(for: openScreen)
        windows = Windows.currentSpace(on: openScreen)
        selectedIndex = windows.count > 1 ? 1 : 0
        hoveredIndex = nil
        openMouseLocation = NSEvent.mouseLocation
        hoverArmed = false
        thumbnails = Dictionary(uniqueKeysWithValues: windows.compactMap { w in
            cache.image(for: w.id).map { (w.id, $0) }
        })
        openTilesPerRow = tilesPerRow(for: windows.count, on: openScreen)
        render()
        positionAndShow()
        print("panel shown in \(Int(Date().timeIntervalSince(t0) * 1000))ms (cached \(thumbnails.count)/\(windows.count))")

        // Fall back to one-shot capture for windows we've never seen.
        captureMissingThumbnails()
    }

    // One-shot capture for windows missing from the cache. Invalidates any
    // earlier run so a stale snapshot cannot land after the list changed.
    private func captureMissingThumbnails() {
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

    // Re-query the Space and keep the overlay open. Used after quitting an app
    // or closing a window so the user can line up the next one without the
    // overlay disappearing. Selection stays at the same slot, which advances
    // to the next tile when the previous one is gone.
    private func refreshWindows() {
        guard active, let screen = openScreen else { return }
        windows = Windows.currentSpace(on: screen)
        guard !windows.isEmpty else {
            print("refresh: no windows left; closing overlay")
            close()
            return
        }
        thumbnails = Dictionary(uniqueKeysWithValues: windows.compactMap { w in
            cache.image(for: w.id).map { (w.id, $0) }
        })
        openTilesPerRow = tilesPerRow(for: windows.count, on: screen)
        selectedIndex = min(selectedIndex, windows.count - 1)
        hoveredIndex = nil
        render(animated: true)
        captureMissingThumbnails()
    }

    // The tile under the selection, whether it was chosen with Tab or hover.
    private var selectedTarget: WindowInfo? {
        let index = hoveredIndex ?? selectedIndex
        return windows.indices.contains(index) ? windows[index] : nil
    }

    func quitSelected() {
        guard isOpen, let target = selectedTarget else { return }
        print("quit: [\(target.pid)] \(target.appName) — \(target.title)")
        guard Windows.quit(target) else { return }
        // A quit takes everything the app owns, so hide all of its tiles.
        hideOptimistically { $0.pid == target.pid }
        // The termination observer confirms a real quit; this fallback puts the
        // tiles back if the app ignored the request or is stuck on a prompt.
        scheduleRefresh(after: 1.5)
    }

    func closeSelectedWindow() {
        guard isOpen, let target = selectedTarget else { return }
        print("close: [\(target.pid)] \(target.appName) — \(target.title)")
        guard Windows.close(target) else { return }
        hideOptimistically { $0.id == target.id }
        // Closing is quick; re-check soon in case the app vetoed it.
        scheduleRefresh(after: 0.35)
    }

    func minimizeSelected() {
        guard isOpen, let target = selectedTarget else { return }
        print("minimize: [\(target.pid)] \(target.appName) — \(target.title)")
        guard Windows.minimize(target) else { return }
        hideOptimistically { $0.id == target.id }
        // The genie keeps the window "on screen" for a beat, so re-check after
        // it settles in case the minimize was ignored.
        scheduleRefresh(after: 0.6)
    }

    // Drop the matching tiles immediately so the action feels instant; the
    // later re-query either confirms it or restores anything that came back.
    private func hideOptimistically(_ shouldHide: (WindowInfo) -> Bool) {
        let remaining = windows.filter { !shouldHide($0) }
        guard remaining.count != windows.count else { return }
        windows = remaining
        guard !windows.isEmpty else {
            close()
            return
        }
        hoveredIndex = nil
        selectedIndex = min(selectedIndex, windows.count - 1)
        openTilesPerRow = tilesPerRow(for: windows.count, on: openScreen)
        render(animated: true)
    }

    // Re-query after an optimistic change. Idempotent: if the window list
    // already matches, the render is a no-op.
    private func scheduleRefresh(after delay: TimeInterval) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.refreshWindows()
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
        hoveredIndex = nil  // keyboard takes over from a resting cursor
        render()
    }

    func commit(at index: Int) {
        guard windows.indices.contains(index) else { return }
        selectedIndex = index
        hoveredIndex = nil
        commit()
    }

    func hover(over index: Int) {
        guard isOpen, windows.indices.contains(index) else { return }
        // The panel opens centered, often right under the resting cursor;
        // require real mouse movement before hover may steal the selection
        // from the default previous-window target.
        if !hoverArmed {
            let loc = NSEvent.mouseLocation
            guard hypot(loc.x - openMouseLocation.x, loc.y - openMouseLocation.y) > 5 else { return }
            hoverArmed = true
        }
        guard index != hoveredIndex else { return }
        hoveredIndex = index
        render()
    }

    func hoverEnded(at index: Int) {
        guard hoveredIndex == index else { return }
        hoveredIndex = nil
        guard isOpen else { return }
        render()
    }

    func commit() {
        guard isOpen else { print("commit: not open, ignoring"); return }
        let index = hoveredIndex ?? selectedIndex
        let target = windows.indices.contains(index) ? windows[index] : nil
        close()
        if let target {
            print("commit: raising [\(target.pid)] \(target.appName) — \(target.title)")
            Windows.raise(target)
        } else {
            print("commit: no target at index \(index) (windows.count=\(windows.count))")
        }
    }

    func close() {
        active = false
        openGeneration &+= 1
        openSpaceIDs = []
        panel.orderOut(nil)
    }

    private func handleActiveSpaceDidChange() {
        guard active || panel.isVisible else { return }
        print("switcher: active Space changed; clearing overlay state")
        close()
    }

    private func isStillInOpeningSpace() -> Bool {
        guard !openSpaceIDs.isEmpty else { return panel.isVisible }
        let current = Spaces.currentSpaceIDs(for: openScreen)
        guard !current.isEmpty else { return panel.isVisible }
        return !current.isDisjoint(with: openSpaceIDs)
    }

    private func render(animated: Bool = false) {
        let view = OverlayView(
            windows: windows,
            thumbnails: thumbnails,
            selectedIndex: selectedIndex,
            hoveredIndex: hoveredIndex,
            maxTilesPerRow: openTilesPerRow,
            onSelect: { [weak self] idx in self?.commit(at: idx) },
            onHover: { [weak self] idx in self?.hover(over: idx) },
            onHoverEnd: { [weak self] idx in self?.hoverEnded(at: idx) }
        )
        let h = hosting ?? {
            let h = FirstMouseHostingView(rootView: view)
            hosting = h
            panel.contentView = h
            return h
        }()
        // A tile leaving the list fades and shrinks instead of popping; the
        // transaction also animates the remaining tiles into their new slots.
        if animated {
            withAnimation(.easeInOut(duration: tileRemovalDuration)) {
                h.rootView = view
            }
        } else {
            h.rootView = view
        }
        resizePanel(to: h.fittingSize, animated: animated)
    }

    // The panel is sized to its content, so a shrinking list would snap the
    // window while the tiles are still animating. Grow/shrink it on the same
    // curve so the whole overlay moves as one.
    private func resizePanel(to size: CGSize, animated: Bool) {
        guard animated, panel.isVisible, let screen = openScreen else {
            panel.setContentSize(size)
            return
        }
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = tileRemovalDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func currentScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    }

    private func tilesPerRow(for count: Int, on screen: NSScreen?) -> Int {
        guard count > 1 else { return max(1, count) }
        let available = (screen?.visibleFrame.width ?? 1280) - screenMargin * 2 - overlayPadding * 2
        let fit = max(1, Int((available + tileSpacing) / (tileWidth + tileSpacing)))
        return min(count, fit)
    }

    private func centerPanel() {
        guard let screen = openScreen else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        ))
    }

    private func positionAndShow() {
        centerPanel()
        // Force a fresh Space association on every show. AppKit can report an
        // ordered panel as visible after a Space change even when WindowServer
        // is still holding it on the previous Space; ordering out first plus
        // moveToActiveSpace makes the next Cmd+Tab create a visible panel in
        // the active workspace.
        panel.orderOut(nil)
        panel.collectionBehavior = overlayCollectionBehavior
        panel.orderFrontRegardless()
    }
}
