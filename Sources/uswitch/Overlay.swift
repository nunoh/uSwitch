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

private let tileSpacing: CGFloat = 12
private let overlayPadding: CGFloat = 20
private let screenMargin: CGFloat = 80
private let minimizedTileWidth: CGFloat = 140
private let minimizedTileHeight: CGFloat = 28
private let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
    .moveToActiveSpace,
    .transient,
    .stationary,
    .ignoresCycle,
    .fullScreenAuxiliary,
]

// How long a tile takes to leave the overlay after quit / close / minimize.
// Short on purpose: a gentle fade and shrink, not a production.
private let tileRemovalDuration: TimeInterval = 0.16

// A window paired with its index in the flat selection order, so a tile can
// report which slot it is without recomputing the layout.
struct IndexedWindow: Identifiable {
    let index: Int
    let window: WindowInfo
    var id: CGWindowID { window.id }
}

// One visual group: the current-Space list has a single, untitled section,
// while the all-Spaces overview has one titled section per Space.
struct OverlaySection: Identifiable {
    let id: String
    let title: String?
    let isCurrent: Bool
    let scale: CGFloat
    let maxTilesPerRow: Int
    let active: [IndexedWindow]
    let minimized: [IndexedWindow]
}

struct ThumbnailTile: View {
    let window: WindowInfo
    let thumbnail: NSImage?
    let selected: Bool
    let hovered: Bool
    // 1 for the current Space; smaller for the other Spaces in the overview.
    let scale: CGFloat
    let tile: TileMetrics

    private var w: CGFloat { tile.width * scale }
    private var h: CGFloat { tile.height * scale }
    private var appIconSize: CGFloat { tile.icon * scale }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.25))

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(width: w - 8, height: h - 8)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if let appIcon = window.icon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: appIconSize, height: appIconSize)
                        .shadow(radius: 2)
                }
            }
            .frame(width: w, height: h)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(strokeColor, lineWidth: selected ? 2.5 : 1.5)
            )

            Text(label)
                .font(.system(size: max(9, 12 * scale), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.middle)
                .frame(width: w)
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

// A minimized window can't be thumbnail-captured, and a squashed preview reads
// as "small window" rather than "in the Dock". A compact icon + title strip
// conveys the state directly, and it is the same shape in both switcher modes.
struct MinimizedTile: View {
    let window: WindowInfo
    let selected: Bool
    let hovered: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .frame(width: minimizedTileWidth, height: minimizedTileHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(strokeColor, lineWidth: selected ? 2 : 1)
        )
    }

    private var label: String {
        window.title.isEmpty ? window.appName : window.title
    }

    private var fillColor: Color {
        if selected { return Color.white.opacity(0.18) }
        if hovered { return Color.white.opacity(0.10) }
        return Color.white.opacity(0.06)
    }

    private var strokeColor: Color {
        if selected { return .accentColor }
        if hovered { return Color.white.opacity(0.5) }
        return Color.white.opacity(0.12)
    }
}

struct SectionHeader: View {
    let title: String
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
            if isCurrent {
                Text("current")
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
    }
}

// The panel never becomes key, so every click arrives as a "first mouse";
// without this override SwiftUI tap gestures inside the panel are dropped.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct OverlayView: View {
    let sections: [OverlaySection]
    let thumbnails: [CGWindowID: NSImage]
    let selectedIndex: Int
    let hoveredIndex: Int?
    let tile: TileMetrics
    let maxHeight: CGFloat
    let onSelect: (Int) -> Void
    let onHover: (Int) -> Void
    let onHoverEnd: (Int) -> Void

    private var isEmpty: Bool {
        sections.allSatisfy { $0.active.isEmpty && $0.minimized.isEmpty }
    }

    var body: some View {
        Group {
            if isEmpty {
                Color.clear.frame(width: tile.width * 0.25, height: tile.height * 0.25)
            } else {
                // A vertical scroller: many windows or many Spaces make the
                // overlay taller than the screen, and it must scroll down rather
                // than run off the edge.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: tileSpacing * 1.4) {
                        ForEach(sections) { section in
                            if !section.active.isEmpty || !section.minimized.isEmpty {
                                VStack(alignment: .leading, spacing: tileSpacing) {
                                    if let title = section.title {
                                        SectionHeader(title: title, isCurrent: section.isCurrent)
                                    }
                                    activeRows(
                                        section.active,
                                        scale: section.scale,
                                        maxTilesPerRow: section.maxTilesPerRow
                                    )
                                    if !section.minimized.isEmpty {
                                        minimizedBlock(
                                            section.minimized,
                                            maxTilesPerRow: section.maxTilesPerRow
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(overlayPadding)
                }
                .frame(maxHeight: maxHeight)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func activeRows(_ windows: [IndexedWindow], scale: CGFloat, maxTilesPerRow: Int) -> some View {
        let rows = chunked(windows, size: max(1, maxTilesPerRow))
        VStack(alignment: .leading, spacing: tileSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: tileSpacing) {
                    ForEach(row) { item in
                        ThumbnailTile(
                            window: item.window,
                            thumbnail: thumbnails[item.window.id],
                            selected: item.index == selectedIndex,
                            hovered: item.index == hoveredIndex,
                            scale: scale,
                            tile: tile
                        )
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(item.index) }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active: onHover(item.index)
                            case .ended: onHoverEnd(item.index)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func minimizedBlock(_ windows: [IndexedWindow], maxTilesPerRow: Int) -> some View {
        let rows = chunked(windows, size: max(1, maxTilesPerRow))
        VStack(alignment: .leading, spacing: 6) {
            Text("MINIMIZED")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { item in
                            MinimizedTile(
                                window: item.window,
                                selected: item.index == selectedIndex,
                                hovered: item.index == hoveredIndex
                            )
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(item.index) }
                            .onContinuousHover { phase in
                                switch phase {
                                case .active: onHover(item.index)
                                case .ended: onHoverEnd(item.index)
                                }
                            }
                        }
                    }
                }
            }
        }
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
    enum Mode { case currentSpace, allSpaces }

    // One visual group, in display order. `active` precedes `minimized`, which
    // is exactly the flat selection order the switcher cycles through.
    private struct SpaceSection {
        let spaceID: CGSSpaceID?
        let title: String?
        let isCurrent: Bool
        var active: [WindowInfo]
        var minimized: [WindowInfo]
    }

    private let panel = OverlayPanel()
    private var hosting: NSHostingView<OverlayView>?
    private var sections: [SpaceSection] = []
    private var mode: Mode = .currentSpace
    // Window ids in the enumerator's front-to-back (MRU) order, before grouping.
    // Used to pick the default target independent of section order.
    private var loadOrder: [CGWindowID] = []
    private var thumbnails: [CGWindowID: NSImage] = [:]
    private var selectedIndex: Int = 0
    private var hoveredIndex: Int?
    private var openGeneration: Int = 0
    private var openScreen: NSScreen?
    private var openSpaceIDs: Set<CGSSpaceID> = []
    private var openMouseLocation: CGPoint = .zero
    private var hoverArmed = false
    // Flick grace: the panel is ordered in transparent and revealed after
    // `flickDelay`; a quick tap that commits first never flashes it.
    private var revealed = false
    private var revealWorkItem: DispatchWorkItem?
    private var activeSpaceObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var active = false
    private let cache: ThumbnailCache

    private var windows: [WindowInfo] { sections.flatMap { $0.active + $0.minimized } }

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

    func open() { open(mode: .currentSpace) }

    func openOverview() { open(mode: .allSpaces) }

    private func open(mode: Mode) {
        let t0 = Date()
        active = true
        self.mode = mode
        openScreen = currentScreen()
        loadWindows()
        selectedIndex = initialSelection()
        hoveredIndex = nil
        openMouseLocation = NSEvent.mouseLocation
        hoverArmed = false
        thumbnails = Dictionary(uniqueKeysWithValues: windows.compactMap { w in
            cache.image(for: w.id).map { (w.id, $0) }
        })
        render()
        positionAndShow()
        print("panel shown (\(mode)) in \(Int(Date().timeIntervalSince(t0) * 1000))ms (cached \(thumbnails.count)/\(windows.count))")

        // Fall back to one-shot capture for windows we've never seen.
        captureMissingThumbnails()
    }

    // Populate `sections` for the active mode. Shared by open() and refresh so
    // both paths agree on ordering.
    private func loadWindows() {
        guard let screen = openScreen else {
            sections = []
            openSpaceIDs = []
            return
        }
        switch mode {
        case .currentSpace:
            let list = Windows.currentSpace(on: screen)
            loadOrder = list.map(\.id)
            let parts = split(list)
            sections = [SpaceSection(
                spaceID: nil,
                title: nil,
                isCurrent: true,
                active: parts.active,
                minimized: parts.minimized
            )]
            openSpaceIDs = Spaces.currentSpaceIDs(for: screen)
        case .allSpaces:
            let descriptors = Spaces.orderedSpaces(for: screen)
            let list = Windows.allSpaces(on: screen)
            loadOrder = list.map(\.id)
            sections = overviewSections(list: list, descriptors: descriptors)
            openSpaceIDs = Set(descriptors.map(\.id))
        }
    }

    // Split windows into the active row and the minimized strip, honoring the
    // "show minimized" setting.
    private func split(_ list: [WindowInfo]) -> (active: [WindowInfo], minimized: [WindowInfo]) {
        let active = list.filter { !$0.isMinimized }
        guard Settings.shared.minimizedShown else { return (active, []) }
        return (active, list.filter { $0.isMinimized })
    }

    // One section per Space, in Space order (Space 1, Space 2, …), each holding
    // its active windows then its minimized strip. The current Space is marked
    // but not moved to the front — the order stays stable.
    private func overviewSections(
        list: [WindowInfo],
        descriptors: [Spaces.SpaceDescriptor]
    ) -> [SpaceSection] {
        var result = descriptors.map { descriptor -> SpaceSection in
            let parts = split(list.filter { $0.spaceID == descriptor.id })
            return SpaceSection(
                spaceID: descriptor.id,
                title: descriptor.label,
                isCurrent: descriptor.isCurrent,
                active: parts.active,
                minimized: parts.minimized
            )
        }
        // Windows whose Space could not be resolved land in a trailing group
        // rather than vanishing.
        let unassigned = list.filter { $0.spaceID == nil }
        if !unassigned.isEmpty {
            let parts = split(unassigned)
            result.append(SpaceSection(
                spaceID: nil,
                title: descriptors.isEmpty ? nil : "Other",
                isCurrent: false,
                active: parts.active,
                minimized: parts.minimized
            ))
        }
        return result.filter { !$0.active.isEmpty || !$0.minimized.isEmpty }
    }

    // One-shot capture for windows missing from the cache. Invalidates any
    // earlier run so a stale snapshot cannot land after the list changed.
    private func captureMissingThumbnails() {
        let missing = windows.filter { thumbnails[$0.id] == nil && !$0.isMinimized && $0.isOnScreen }
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
        guard active else { return }
        loadWindows()
        guard !windows.isEmpty else {
            print("refresh: no windows left; closing overlay")
            close()
            return
        }
        thumbnails = Dictionary(uniqueKeysWithValues: windows.compactMap { w in
            cache.image(for: w.id).map { (w.id, $0) }
        })
        clampSelection()
        hoveredIndex = nil
        render(animated: true)
        captureMissingThumbnails()
    }

    // The tile under the selection, whether it was chosen with Tab or hover.
    private var selectedTarget: WindowInfo? {
        let index = hoveredIndex ?? selectedIndex
        let list = windows
        return list.indices.contains(index) ? list[index] : nil
    }

    func quitSelected() {
        guard isOpen, let target = selectedTarget else { return }
        print("quit: [\(target.pid)] \(target.appName) — \(target.title)")
        guard Windows.quit(target) else { return }
        // A quit takes everything the app owns, so hide all of its tiles.
        removeWindows { $0.pid == target.pid }
        // The termination observer confirms a real quit; this fallback puts the
        // tiles back if the app ignored the request or is stuck on a prompt.
        scheduleRefresh(after: 1.5)
    }

    func closeSelectedWindow() {
        guard isOpen, let target = selectedTarget else { return }
        print("close: [\(target.pid)] \(target.appName) — \(target.title)")
        guard Windows.close(target) else { return }
        removeWindows { $0.id == target.id }
        // Closing is quick; re-check soon in case the app vetoed it.
        scheduleRefresh(after: 0.35)
    }

    func minimizeSelected() {
        guard isOpen, let target = selectedTarget else { return }
        print("minimize: [\(target.pid)] \(target.appName) — \(target.title)")
        guard Windows.minimize(target) else { return }
        // The window stays in the list — it just drops into the minimized strip
        // instead of disappearing.
        moveToMinimized(windowID: target.id)
        // The genie keeps the window "on screen" for a beat, so re-check after
        // it settles in case the minimize was ignored.
        scheduleRefresh(after: 0.6)
    }

    private func moveToMinimized(windowID: CGWindowID) {
        for i in sections.indices {
            guard let idx = sections[i].active.firstIndex(where: { $0.id == windowID }) else { continue }
            var window = sections[i].active.remove(at: idx)
            window.isMinimized = true
            sections[i].minimized.append(window)
            break
        }
        hoveredIndex = nil
        clampSelection()
        render(animated: true)
    }

    // Drop the matching tiles immediately so the action feels instant; the
    // later re-query either confirms it or restores anything that came back.
    private func removeWindows(_ shouldRemove: (WindowInfo) -> Bool) {
        let before = windows.count
        for i in sections.indices {
            sections[i].active.removeAll(where: shouldRemove)
            sections[i].minimized.removeAll(where: shouldRemove)
        }
        guard windows.count != before else { return }
        guard !windows.isEmpty else {
            close()
            return
        }
        hoveredIndex = nil
        clampSelection()
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

    // Minimized windows are shown in their own strip but are not part of the
    // keyboard cycle — Tab only ever lands on a real (active) window.
    private var cycleIndices: [Int] {
        if Settings.shared.minimizedInCycle { return Array(windows.indices) }
        return windows.indices.filter { !windows[$0].isMinimized }
    }

    private func initialSelection() -> Int {
        // Start in the current Space, exactly like the plain switcher — even
        // though the overview renders sections in Space order. Within the
        // current Space this is the previous window (second in MRU order).
        if let current = sections.first(where: { $0.isCurrent }) {
            let active = current.active
            let pick = active.count > 1 ? active[1].id : active.first?.id
            if let pick, let index = windows.firstIndex(where: { $0.id == pick }) {
                return index
            }
        }
        // Fallback: previous window in the enumerator's MRU order.
        let active = loadOrder.filter { id in
            windows.first(where: { $0.id == id })?.isMinimized == false
        }
        let pick = active.count > 1 ? active[1] : active.first
        if let pick, let index = windows.firstIndex(where: { $0.id == pick }) {
            return index
        }
        return cycleIndices.first ?? 0
    }

    // Keep the selection on a cyclable tile after the list changes (a window
    // was minimized, closed, or quit).
    private func clampSelection() {
        let selectable = cycleIndices
        guard !selectable.isEmpty else { selectedIndex = 0; return }
        if selectable.contains(selectedIndex) { return }
        selectedIndex = selectable.last(where: { $0 < selectedIndex }) ?? selectable[0]
    }

    func cycle(backward: Bool) {
        let order = cycleIndices
        guard !order.isEmpty else { return }
        // Cycling is intent to browse — reveal immediately.
        reveal()
        let current = order.firstIndex(of: selectedIndex) ?? 0
        let step = backward ? -1 : 1
        selectedIndex = order[(current + step + order.count) % order.count]
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
        reveal()
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
        let list = windows
        let target = list.indices.contains(index) ? list[index] : nil
        close()
        if let target {
            print("commit: raising [\(target.pid)] \(target.appName) — \(target.title) minimized=\(target.isMinimized)")
            Windows.raise(target)
        } else {
            print("commit: no target at index \(index) (windows.count=\(list.count))")
        }
    }

    func close() {
        active = false
        revealWorkItem?.cancel()
        revealWorkItem = nil
        revealed = false
        openGeneration &+= 1
        openSpaceIDs = []
        panel.alphaValue = 1
        panel.orderOut(nil)
    }

    private func handleActiveSpaceDidChange() {
        guard active || panel.isVisible else { return }
        // The overview deliberately spans every Space, so a Space change while
        // it is up (a fullscreen app taking over, say) must not tear it down.
        if mode == .allSpaces { return }
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
            sections: overlaySections(),
            thumbnails: thumbnails,
            selectedIndex: selectedIndex,
            hoveredIndex: hoveredIndex,
            tile: Settings.shared.tileSize.metrics,
            maxHeight: overlayMaxHeight(),
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

    // Flatten the sections into the display model, assigning each window its
    // index in the global selection order. Non-current Spaces scale down.
    private func overlaySections() -> [OverlaySection] {
        var index = 0
        return sections.map { section in
            let active = section.active.map { window -> IndexedWindow in
                defer { index += 1 }
                return IndexedWindow(index: index, window: window)
            }
            let minimized = section.minimized.map { window -> IndexedWindow in
                defer { index += 1 }
                return IndexedWindow(index: index, window: window)
            }
            let scale: CGFloat = section.isCurrent ? 1 : CGFloat(Settings.shared.otherSpaceScale)
            return OverlaySection(
                id: section.spaceID.map(String.init) ?? "flat",
                title: section.title,
                isCurrent: section.isCurrent,
                scale: scale,
                maxTilesPerRow: tilesPerRow(
                    for: section.active.count,
                    scale: scale,
                    on: openScreen,
                    tile: Settings.shared.tileSize.metrics
                ),
                active: active,
                minimized: minimized
            )
        }
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

    // Height the overlay may reach before it scrolls, leaving a margin top and
    // bottom so it never runs off the screen.
    private func overlayMaxHeight() -> CGFloat {
        let screenHeight = openScreen?.visibleFrame.height ?? 800
        return max(200, screenHeight - 120)
    }

    private func tilesPerRow(
        for count: Int,
        scale: CGFloat,
        on screen: NSScreen?,
        tile: TileMetrics
    ) -> Int {
        guard count > 1 else { return max(1, count) }
        let available = (screen?.visibleFrame.width ?? 1280) - screenMargin * 2 - overlayPadding * 2
        let scaledTileWidth = tile.width * scale
        let fit = max(1, Int((available + tileSpacing) / (scaledTileWidth + tileSpacing)))
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
        // moveToActiveSpace makes the next trigger create a visible panel in the
        // active workspace.
        panel.orderOut(nil)
        panel.collectionBehavior = overlayCollectionBehavior
        // Start transparent and reveal after the flick delay: a quick tap that
        // commits before then never flashes the overlay.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        revealed = false
        let delay = Settings.shared.flickDelay
        guard delay > 0 else {
            reveal()
            return
        }
        let item = DispatchWorkItem { [weak self] in self?.reveal() }
        revealWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // Reveal the overlay and cancel the pending reveal timer.
    private func reveal() {
        revealWorkItem?.cancel()
        revealWorkItem = nil
        guard active, !revealed else { return }
        revealed = true
        panel.alphaValue = 1
    }
}
