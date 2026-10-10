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

let tileSpacing: CGFloat = 12
let overlayPadding: CGFloat = 20
private let screenMargin: CGFloat = 80
// Keeps the overlay clear of the menu bar / Dock when it is taller than the
// centered content (i.e. when the minimized strip extends it downward).
private let overlayVerticalMargin: CGFloat = 60
// Minimized windows can't be thumbnail-captured, so each one is a single app
// icon ("favicon") rather than a titled strip.
private let minimizedTileSize: CGFloat = 30
private let minimizedTileSpacing: CGFloat = 8
// Extra breathing room above the minimized strip so the icons read as their
// own row rather than crowding the window thumbnails above them.
private let minimizedStripTopMargin: CGFloat = 8
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
// Minimizing instead sends the icon on a short flight from the tile down into
// the icon strip. A little longer than a removal so the arc reads, and the
// panel resize uses the same duration so the strip grows in step with it.
private let minimizeFlightDuration: TimeInterval = 0.34

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
    // Minimized tiles are much narrower than thumbnails, so they get their own
    // per-row count: they sit side by side until the width runs out.
    let minimizedPerRow: Int
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
// as "small window" rather than "in the Dock". A single app icon conveys the
// state directly, and it is the same shape in both switcher modes. The window
// title is still available as a tooltip.
struct MinimizedTile: View {
    let window: WindowInfo
    let selected: Bool
    let hovered: Bool
    // Opacity of the icon when the tile is neither selected nor hovered.
    let idleOpacity: CGFloat

    var body: some View {
        ZStack {
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: minimizedTileSize - 10, height: minimizedTileSize - 10)
                    .opacity(iconOpacity)
            } else {
                Text(String(window.appName.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(iconOpacity)
            }
        }
        .frame(width: minimizedTileSize, height: minimizedTileSize)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(strokeColor, lineWidth: selected ? 2 : 1)
        )
        .help(label)
    }

    private var label: String {
        window.title.isEmpty ? window.appName : window.title
    }

    // Faded while idle, solid when it is the target so it stays legible.
    private var iconOpacity: CGFloat {
        (selected || hovered) ? 1 : idleOpacity
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

// The overlay's render state. The hosting view observes a single, long-lived
// instance so that SwiftUI sees steady updates instead of a brand-new root view
// every render. That steady identity is what lets `@Namespace` (and therefore
// `matchedGeometryEffect`) persist across a minimize.
@MainActor
final class OverlayModel: ObservableObject {
    @Published var sections: [OverlaySection] = []
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var selectedIndex: Int = 0
    @Published var hoveredIndex: Int?
    @Published var tile: TileMetrics = Settings.shared.tileSize.metrics
    @Published var maxHeight: CGFloat = 800
    @Published var minimizedIconOpacity: CGFloat = CGFloat(Settings.defaultMinimizedIconOpacity)
    var onSelect: (Int) -> Void = { _ in }
    var onHover: (Int) -> Void = { _ in }
    var onHoverEnd: (Int) -> Void = { _ in }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    // Shared between a window's active thumbnail and its minimized icon so that
    // minimizing sends the icon flying from the tile down into the icon strip.
    // Owned by the persistent host, so it survives every render pass.
    let iconFlight: Namespace.ID

    private var sections: [OverlaySection] { model.sections }
    private var thumbnails: [CGWindowID: NSImage] { model.thumbnails }
    private var selectedIndex: Int { model.selectedIndex }
    private var hoveredIndex: Int? { model.hoveredIndex }
    private var tile: TileMetrics { model.tile }
    private var maxHeight: CGFloat { model.maxHeight }
    private var minimizedIconOpacity: CGFloat { model.minimizedIconOpacity }
    private var onSelect: (Int) -> Void { model.onSelect }
    private var onHover: (Int) -> Void { model.onHover }
    private var onHoverEnd: (Int) -> Void { model.onHoverEnd }

    private var isEmpty: Bool {
        sections.allSatisfy { $0.active.isEmpty && $0.minimized.isEmpty }
    }

    // Only the all-Spaces overview tints its current Space (those sections carry
    // titles; the single current-Space switcher section does not).
    private func highlight(_ section: OverlaySection) -> Bool {
        section.isCurrent && section.title != nil
    }

    var body: some View {
        let overview = sections.contains { $0.title != nil }
        Group {
            if isEmpty {
                Color.clear.frame(width: tile.width * 0.25, height: tile.height * 0.25)
            } else {
                // A vertical scroller: many windows or many Spaces make the
                // overlay taller than the screen, and it must scroll down rather
                // than run off the edge.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
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
                                            maxTilesPerRow: section.minimizedPerRow
                                        )
                                    }
                                }
                                // In the all-Spaces overview, tint the current
                                // Space's section so it reads at a glance even
                                // without noticing the badge.
                                .padding(overview ? 10 : 0)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(highlight(section) ? Color.accentColor.opacity(0.06) : .clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            highlight(section) ? Color.accentColor.opacity(0.25) : .clear,
                                            lineWidth: 1
                                        )
                                )
                            }
                        }
                    }
                    .padding(overlayPadding)
                }
                .scrollIndicators(.hidden)
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
                        .matchedGeometryEffect(id: item.window.id, in: iconFlight)
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
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: minimizedTileSpacing) {
                    ForEach(row) { item in
                        MinimizedTile(
                            window: item.window,
                            selected: item.index == selectedIndex,
                            hovered: item.index == hoveredIndex,
                            idleOpacity: minimizedIconOpacity
                        )
                        .matchedGeometryEffect(id: item.window.id, in: iconFlight)
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
        .padding(.top, minimizedStripTopMargin)
    }

    private func chunked<T>(_ array: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [array] }
        return stride(from: 0, to: array.count, by: size).map {
            Array(array[$0..<min($0 + size, array.count)])
        }
    }
}

// The panel's permanent root view. Because it is installed once and never
// replaced, its `@Namespace` outlives every render pass.
struct OverlayRoot: View {
    @ObservedObject var model: OverlayModel
    @Namespace private var iconFlight

    var body: some View {
        OverlayView(model: model, iconFlight: iconFlight)
    }
}

@MainActor
final class Switcher {
    enum Mode { case currentSpace, allSpaces }

    // Which windows the trigger key steps through: the open ones, the minimized
    // ones, or both together. Fixed by how the overlay was opened.
    enum CycleSet { case open, all }

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
    // The single, long-lived render state observed by the hosting view. Mutating
    // this (inside `withAnimation`) is what animates the overlay — the root view
    // itself is installed once and never swapped.
    private let model = OverlayModel()
    private var hosting: NSHostingView<OverlayRoot>?
    private var sections: [SpaceSection] = []
    private var mode: Mode = .currentSpace
    private var cycleSet: CycleSet = .open
    // Window ids in the enumerator's front-to-back (MRU) order, before grouping.
    // Used to pick the default target independent of section order.
    private var loadOrder: [CGWindowID] = []
    private var thumbnails: [CGWindowID: NSImage] = [:]
    private var selectedIndex: Int = 0
    private var hoveredIndex: Int?
    private var openGeneration: Int = 0
    private var openScreen: NSScreen?
    private var openSpaceIDs: Set<CGSSpaceID> = []
    // Height the overlay would have without the minimized strip. The panel is
    // anchored by its top at the centered position of this height so adding
    // minimized windows grows it downward instead of nudging the live
    // thumbnails up.
    private var anchorHeight: CGFloat = 0
    // True while the minimized-window cycle has selected a minimized tile.
    private var browsingMinimized = false
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
        // Tile interactions are routed through the model (its callbacks are
        // plain stored closures, unlike the old per-render view closures).
        model.onSelect = { [weak self] idx in
            MainActor.assumeIsolated { self?.commit(at: idx) }
        }
        model.onHover = { [weak self] idx in
            MainActor.assumeIsolated { self?.hover(over: idx) }
        }
        model.onHoverEnd = { [weak self] idx in
            MainActor.assumeIsolated { self?.hoverEnded(at: idx) }
        }
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

    func open() { open(mode: .currentSpace, cycle: Settings.shared.minimizedInCycle ? .all : .open) }

    func openAll() { open(mode: .currentSpace, cycle: .all) }

    func openOverview() { open(mode: .allSpaces, cycle: Settings.shared.minimizedInCycle ? .all : .open) }

    func openOverviewAll() { open(mode: .allSpaces, cycle: .all) }

    // Flip between the current-Space switcher and the all-Spaces overview while
    // the overlay stays open, keeping the selected window if it appears in both.
    func toggleMode() {
        guard active else { return }
        reveal()
        let current = hoveredIndex ?? selectedIndex
        let previousID = windows.indices.contains(current) ? windows[current].id : nil
        mode = (mode == .currentSpace) ? .allSpaces : .currentSpace
        loadWindows()
        thumbnails = Dictionary(uniqueKeysWithValues: windows.compactMap { w in
            cache.image(for: w.id).map { (w.id, $0) }
        })
        if let previousID, let index = windows.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = index
        } else {
            selectedIndex = initialSelection()
        }
        hoveredIndex = nil
        render(animated: true)
        captureMissingThumbnails()
    }

    private func open(mode: Mode, cycle: CycleSet) {
        let t0 = Date()
        active = true
        browsingMinimized = false
        self.mode = mode
        self.cycleSet = cycle
        openScreen = currentScreen()
        loadWindows()
        selectedIndex = initialSelection()
        clampSelection()
        hoveredIndex = nil
        openMouseLocation = NSEvent.mouseLocation
        hoverArmed = false
        thumbnails = Dictionary(uniqueKeysWithValues: windows.compactMap { w in
            cache.image(for: w.id).map { (w.id, $0) }
        })
        render()
        positionAndShow()
        print("panel shown (\(mode), cycle=\(cycle)) in \(Int(Date().timeIntervalSince(t0) * 1000))ms (cached \(thumbnails.count)/\(windows.count))")

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
        // Move the tile into the strip the instant the key is pressed. The AX
        // round trip can block the main thread for a long time on a busy app
        // (each call allows a 0.25s messaging timeout), and the flight must not
        // wait on it — the app minimizes on the windowless thread below.
        moveToMinimized(windowID: target.id)
        Task.detached(priority: .userInitiated) { [weak self] in
            let ok = Windows.minimize(target)
            // The app refused to minimize: put the tile back.
            guard !ok else { return }
            await self?.scheduleRefresh(after: 0.2)
        }
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
        render(animated: true, flight: true)
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

    // The windows the trigger key steps through, per the session's cycle set.
    private var cycleIndices: [Int] {
        switch cycleSet {
        case .open:
            return windows.indices.filter { !windows[$0].isMinimized }
        case .all:
            return Array(windows.indices)
        }
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
        if browsingMinimized, windows.indices.contains(selectedIndex), windows[selectedIndex].isMinimized { return }
        selectedIndex = selectable.last(where: { $0 < selectedIndex }) ?? selectable[0]
    }

    // Fn while the overlay is up: cycle minimized windows.
    func cycleMinimized(backward: Bool) {
        guard isOpen else { return }
        let order = windows.indices.filter { windows[$0].isMinimized }
        guard !order.isEmpty else { return }
        reveal()
        browsingMinimized = true
        if let current = order.firstIndex(of: selectedIndex) {
            let step = backward ? -1 : 1
            selectedIndex = order[(current + step + order.count) % order.count]
        } else {
            selectedIndex = backward ? order[order.count - 1] : order[0]
        }
        hoveredIndex = nil
        render()
    }

    func cycle(backward: Bool) {
        let order = cycleIndices
        guard !order.isEmpty else { return }
        browsingMinimized = false
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

    // Cmd+1…9 while open: switch straight to the Nth active window of the
    // current Space. Unlike Tab-cycling this does not wait for Cmd to be
    // released — the window is raised the moment the digit is pressed.
    func selectNumber(_ number: Int) {
        guard isOpen, number >= 1 else { return }
        let ids = numberedWindowIDs
        guard ids.indices.contains(number - 1),
              let index = windows.firstIndex(where: { $0.id == ids[number - 1] })
        else { return }
        commit(at: index)
    }

    // The current Space's first nine active windows, in visual order — the
    // targets for Cmd+1…9. The minimized strip and the other Spaces of the
    // overview are deliberately not addressable by number.
    private var numberedWindowIDs: [CGWindowID] {
        guard let current = sections.first(where: { $0.isCurrent }) else { return [] }
        return current.active.prefix(9).map(\.id)
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
            // Raising a minimized window is several accessibility round trips
            // (unminimize, then focus). Run them once this event has finished
            // processing, so the panel's order-out is committed and the overlay
            // disappears immediately instead of lingering until AX returns.
            DispatchQueue.main.async { Windows.raise(target) }
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

    private func render(animated: Bool = false, flight: Bool = false) {
        let modelSections = overlaySections()
        let metrics = Settings.shared.tileSize.metrics
        let maxH = overlayMaxHeight()

        // Install the persistent host once. Its `@Namespace` — used for the
        // minimize flight — lives as long as the panel, which is what lets
        // matchedGeometryEffect bridge renders.
        if hosting == nil {
            let h = FirstMouseHostingView(rootView: OverlayRoot(model: model))
            hosting = h
            panel.contentView = h
        }

        // A tile leaving the list fades and shrinks instead of popping; the
        // transaction also animates the remaining tiles into their new slots.
        // A minimize flight gets a springy, slightly longer curve so the icon's
        // path down into the strip reads.
        func apply() {
            model.sections = modelSections
            model.thumbnails = thumbnails
            model.selectedIndex = selectedIndex
            model.hoveredIndex = hoveredIndex
            model.tile = metrics
            model.maxHeight = maxH
            model.minimizedIconOpacity = CGFloat(Settings.shared.minimizedIconOpacity)
        }
        if animated {
            let animation: Animation = flight
                ? .interpolatingSpring(stiffness: 210, damping: 24)
                : .easeInOut(duration: tileRemovalDuration)
            withAnimation(animation) { apply() }
        } else {
            apply()
        }

        // Measure against a throwaway host so the panel is sized from the new
        // state right away, rather than waiting on the live host's update pass.
        let size = measure(sections: modelSections, metrics: metrics, maxHeight: maxH)
        anchorHeight = anchorHeight(for: modelSections, fullHeight: size.height)
        resizePanel(to: size, animated: animated, flight: flight)
    }

    // Lay the overlay out in a throwaway host to read its fitting size.
    private func measure(
        sections: [OverlaySection],
        metrics: TileMetrics,
        maxHeight: CGFloat
    ) -> CGSize {
        let probe = OverlayModel()
        probe.sections = sections
        probe.tile = metrics
        probe.maxHeight = maxHeight
        probe.selectedIndex = -1
        return NSHostingView(rootView: OverlayRoot(model: probe)).fittingSize
    }

    // The "no minimized windows" height of the overlay. Measured by laying out
    // the same sections with their minimized strips removed; the panel's top is
    // pinned to the centered position of this height. Falls back to the full
    // height when there is nothing to anchor to (no active windows).
    private func anchorHeight(for sections: [OverlaySection], fullHeight: CGFloat) -> CGFloat {
        let hasMinimized = sections.contains { !$0.minimized.isEmpty }
        let hasActive = sections.contains { !$0.active.isEmpty }
        guard hasMinimized, hasActive else { return fullHeight }

        let stripped = sections.map { section in
            OverlaySection(
                id: section.id,
                title: section.title,
                isCurrent: section.isCurrent,
                scale: section.scale,
                maxTilesPerRow: section.maxTilesPerRow,
                minimizedPerRow: section.minimizedPerRow,
                active: section.active,
                minimized: []
            )
        }
        // Thumbnails and icons never change a tile's frame, so an empty map is
        // enough to measure the layout.
        let probe = OverlayModel()
        probe.sections = stripped
        probe.tile = Settings.shared.tileSize.metrics
        probe.maxHeight = overlayMaxHeight()
        probe.selectedIndex = -1
        return NSHostingView(rootView: OverlayRoot(model: probe)).fittingSize.height
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
                minimizedPerRow: minimizedTilesPerRow(on: openScreen),
                active: active,
                minimized: minimized
            )
        }
    }

    // The panel is sized to its content, so a shrinking list would snap the
    // window while the tiles are still animating. Grow/shrink it on the same
    // curve so the whole overlay moves as one. Its top stays put at the
    // centered position of `anchorHeight`, so extra (minimized) rows extend the
    // overlay downward rather than shifting the live thumbnails upward.
    private func resizePanel(to size: CGSize, animated: Bool, flight: Bool = false) {
        guard animated, panel.isVisible, let screen = openScreen else {
            panel.setContentSize(size)
            return
        }
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: anchorOriginY(for: size, on: screen),
            width: size.width,
            height: size.height
        )
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = flight ? minimizeFlightDuration : tileRemovalDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // Bottom edge for a panel of `size` whose top sits where a vertically
    // centered, `anchorHeight`-tall overlay's top would. When nothing extra is
    // shown (anchor == height) this is plain centering. The bottom is clamped
    // so a very tall minimized strip cannot push the overlay off screen; the
    // scroll view then handles the overflow.
    private func anchorOriginY(for size: CGSize, on screen: NSScreen) -> CGFloat {
        let anchored = screen.frame.midY - size.height + anchorHeight / 2
        let minY = screen.visibleFrame.minY + overlayVerticalMargin
        return max(anchored, minY)
    }

    private func currentScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    }

    // Height the overlay may reach before it scrolls, leaving a margin top and
    // bottom so it never runs off the screen.
    private func overlayMaxHeight() -> CGFloat {
        let screenHeight = openScreen?.visibleFrame.height ?? 800
        return max(200, screenHeight - overlayVerticalMargin * 2)
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

    // How many minimized strips fit on one row. They are fixed-width, so this
    // only depends on the screen: side by side until the width runs out, then
    // wrap onto another row.
    private func minimizedTilesPerRow(on screen: NSScreen?) -> Int {
        let available = (screen?.visibleFrame.width ?? 1280) - screenMargin * 2 - overlayPadding * 2
        return max(1, Int((available + minimizedTileSpacing) / (minimizedTileSize + minimizedTileSpacing)))
    }

    // Horizontally centered, vertically anchored by the top per anchorOriginY.
    private func placePanel() {
        guard let screen = openScreen else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: anchorOriginY(for: size, on: screen)
        ))
    }

    private func positionAndShow() {
        placePanel()
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
