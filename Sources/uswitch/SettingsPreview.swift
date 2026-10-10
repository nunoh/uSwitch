import AppKit
import SwiftUI

// A miniature of the switcher overlay rendered from the live settings, so the
// appearance controls can be tuned without opening the real overlay. It reuses
// OverlayView — the same tiles, material and metrics as the real thing — so the
// preview cannot drift from the actual look.
//
// Only the window *contents* are stand-ins: real thumbnails are screen captures
// that need live windows on screen. They are drawn to look like the macOS apps
// they represent, and every app badge is the genuine system icon, so the sample
// reads like the overlay rather than a diagram of it.
struct OverlayPreview: View {
    @ObservedObject var settings: Settings
    @Namespace private var iconFlight

    // The settings pane is 480 wide; the form insets leave roughly this much
    // for the preview. Kept slightly under the real figure so a larger tile
    // size never clips.
    private static let availableWidth: CGFloat = 440
    private static let padding: CGFloat = 12

    var body: some View {
        let model = makeModel()
        // The real overlay is a content-hugging panel floating over the
        // desktop, its glass sampling the wallpaper behind it. Mirror that: the
        // user's actual wallpaper underneath, a soft drop shadow, and — only
        // when the chosen tile size would overflow this narrow pane — a small
        // scale-down so the sample fits rather than clips.
        OverlayView(model: model, iconFlight: iconFlight)
            .fixedSize()
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            .padding(Self.padding)
            .background(PreviewBackdrop())
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .scaleEffect(scale)
            .frame(width: naturalWidth * scale)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // Width the overlay lays out at, from the real layout constants, so the
    // scale factor can be worked out without measuring at runtime.
    private var naturalWidth: CGFloat {
        let tile = settings.tileSize.metrics.width
        return 2 * tile + tileSpacing + overlayPadding * 2 + Self.padding * 2
    }

    private var scale: CGFloat {
        min(1, Self.availableWidth / naturalWidth)
    }

    // Build the overlay's render state from the current settings. A fresh model
    // per pass is fine: the preview never animates, so it needs no long-lived
    // identity the way the real overlay does.
    private func makeModel() -> OverlayModel {
        let model = OverlayModel()
        model.tile = settings.tileSize.metrics
        model.maxHeight = 400
        model.minimizedIconOpacity = CGFloat(settings.minimizedIconOpacity)
        // Show one selected thumbnail and one hovered minimized icon, so both
        // the accent selection and the "solid when targeted" icon are visible.
        model.selectedIndex = 0
        model.hoveredIndex = 4

        model.sections = [previewSection()]
        model.thumbnails = [
            1: MockWindow.safari,
            2: MockWindow.finder,
        ]
        return model
    }

    private func previewSection() -> OverlaySection {
        let active = [
            sampleWindow(id: 1, title: "Apple — Safari", app: "Safari", bundleID: "com.apple.Safari"),
            sampleWindow(id: 2, title: "Documents", app: "Finder", bundleID: "com.apple.finder"),
        ]
        let minimized = settings.minimizedShown ? [
            sampleWindow(id: 3, title: "Inbox", app: "Mail", bundleID: "com.apple.mail"),
            sampleWindow(id: 4, title: "September", app: "Calendar", bundleID: "com.apple.iCal"),
            sampleWindow(id: 5, title: "Now Playing", app: "Music", bundleID: "com.apple.Music"),
            sampleWindow(id: 6, title: "Notes", app: "Notes", bundleID: "com.apple.Notes"),
        ] : []

        var index = 0
        let indexedActive = active.map { window -> IndexedWindow in
            defer { index += 1 }
            return IndexedWindow(index: index, window: window)
        }
        let indexedMinimized = minimized.map { window -> IndexedWindow in
            defer { index += 1 }
            return IndexedWindow(index: index, window: window)
        }

        return OverlaySection(
            id: "preview",
            title: nil,
            isCurrent: true,
            scale: 1,
            maxTilesPerRow: max(1, active.count),
            minimizedPerRow: 8,
            active: indexedActive,
            minimized: indexedMinimized
        )
    }

    private func sampleWindow(
        id: CGWindowID,
        title: String,
        app: String,
        bundleID: String
    ) -> WindowInfo {
        WindowInfo(
            id: id,
            pid: pid_t(id),
            title: title,
            appName: app,
            bounds: .zero,
            iconOverride: AppIcons.icon(bundleID: bundleID)
        )
    }
}

// The user's desktop picture, so the translucent overlay is judged against the
// real thing. Falls back to a neutral gradient when no picture is available.
private struct PreviewBackdrop: View {
    var body: some View {
        ZStack {
            if let wallpaper = Self.wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.13, blue: 0.20),
                        Color(red: 0.17, green: 0.10, blue: 0.19),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // A touch of shade so the white tile labels stay legible over a
            // bright picture.
            Color.black.opacity(0.18)
        }
    }

    private static let wallpaper: NSImage? = {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen)
        else { return nil }
        return NSImage(contentsOf: url)
    }()
}

// The genuine icon for a bundle id, exactly as the overlay badges windows. The
// preview's sample pids are fake, so WindowInfo's running-app lookup can't
// supply these — they are resolved once from the installed apps and cached.
@MainActor
private enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        let path = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID)?
            .path
            ?? fallbackPaths[bundleID]
        guard let path else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[bundleID] = icon
        return icon
    }

    // Some system apps live outside the usual search paths.
    private static let fallbackPaths: [String: String] = [
        "com.apple.finder": "/System/Library/CoreServices/Finder.app",
        "com.apple.mail": "/System/Applications/Mail.app",
        "com.apple.iCal": "/System/Applications/Calendar.app",
        "com.apple.Music": "/System/Applications/Music.app",
        "com.apple.Notes": "/System/Applications/Notes.app",
        "com.apple.Safari": "/Applications/Safari.app",
    ]
}

// Stand-ins for live window thumbnails: a macOS window chrome plus content that
// reads as the app it stands for. Sized 3:2 to match a tile.
private enum MockWindow {
    static let safari = draw { W, H, barH in
        fill(NSRect(x: 0, y: barH, width: W, height: H - barH), NSColor(calibratedWhite: 1.0, alpha: 1))
        toolbar(W: W, barH: barH)
        // Address field.
        let fieldW = W * 0.44
        fill(
            NSRect(x: (W - fieldW) / 2, y: (barH - 22) / 2, width: fieldW, height: 22),
            NSColor(calibratedWhite: 0.88, alpha: 1),
            radius: 6
        )
        // Page content: a heading, a hero block, then article lines.
        fill(NSRect(x: 40, y: barH + 34, width: 190, height: 14), NSColor(calibratedWhite: 0.78, alpha: 1), radius: 3)
        fill(
            NSRect(x: 40, y: barH + 66, width: W - 80, height: 96),
            NSColor(calibratedHue: 0.58, saturation: 0.30, brightness: 0.96, alpha: 1),
            radius: 6
        )
        for (i, fraction) in [0.9, 0.74, 0.82, 0.58].enumerated() {
            fill(
                NSRect(x: 40, y: barH + 178 + CGFloat(i) * 20, width: (W - 80) * fraction, height: 8),
                NSColor(calibratedWhite: 0.86, alpha: 1),
                radius: 4
            )
        }
    }

    static let finder = draw { W, H, barH in
        fill(NSRect(x: 0, y: barH, width: W, height: H - barH), NSColor(calibratedWhite: 1.0, alpha: 1))
        // Sidebar.
        let sideW = (W * 0.28).rounded()
        fill(NSRect(x: 0, y: barH, width: sideW, height: H - barH), NSColor(calibratedWhite: 0.93, alpha: 1))
        fill(NSRect(x: sideW, y: barH, width: 1, height: H - barH), NSColor(calibratedWhite: 0.86, alpha: 1))
        toolbar(W: W, barH: barH)
        let tints: [NSColor] = [.systemBlue, .systemTeal, .systemOrange, .systemPink, .systemPurple, .systemGray]
        for i in 0..<6 {
            let y = barH + 22 + CGFloat(i) * 30
            fill(NSRect(x: 16, y: y, width: 12, height: 12), tints[i].withAlphaComponent(0.9), radius: 3)
            fill(NSRect(x: 36, y: y + 2, width: 54, height: 7), NSColor(calibratedWhite: 0.72, alpha: 1), radius: 3)
        }
        // File list.
        for i in 0..<5 {
            let y = barH + 22 + CGFloat(i) * 34
            fill(
                NSRect(x: sideW + 24, y: y, width: 26, height: 20),
                NSColor(calibratedHue: 0.58, saturation: 0.5, brightness: 0.96, alpha: 1),
                radius: 4
            )
            fill(
                NSRect(x: sideW + 60, y: y + 6, width: (W - sideW - 110) * (i.isMultiple(of: 2) ? 0.72 : 0.5), height: 8),
                NSColor(calibratedWhite: 0.8, alpha: 1),
                radius: 4
            )
        }
    }

    // Draw a 480×320 (3:2) window image, top-left origin like the content it
    // imitates.
    private static func draw(_ body: @escaping (_ W: CGFloat, _ H: CGFloat, _ barH: CGFloat) -> Void) -> NSImage {
        let size = NSSize(width: 480, height: 320)
        return NSImage(size: size, flipped: true) { rect in
            body(rect.width, rect.height, 44)
            return true
        }
    }

    private static func toolbar(W: CGFloat, barH: CGFloat) {
        fill(NSRect(x: 0, y: 0, width: W, height: barH), NSColor(calibratedWhite: 0.95, alpha: 1))
        fill(NSRect(x: 0, y: barH - 1, width: W, height: 1), NSColor(calibratedWhite: 0.82, alpha: 1))
        let lights: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
        for (i, color) in lights.enumerated() {
            fill(
                NSRect(x: 18 + CGFloat(i) * 20, y: (barH - 12) / 2, width: 12, height: 12),
                color,
                radius: 6
            )
        }
    }
}

// Paints a rectangle, or a rounded card when a radius is given.
private func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) {
    color.setFill()
    if radius > 0 {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    } else {
        NSBezierPath(rect: rect).fill()
    }
}
