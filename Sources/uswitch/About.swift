import AppKit
import SwiftUI

private let repoURL = URL(string: "https://github.com/nunoh/uSwitch")!
private let issuesURL = URL(string: "https://github.com/nunoh/uSwitch/issues")!

private final class CloseableWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
func presentSingleton<V: View>(
    _ window: inout NSWindow?,
    title: String,
    size: NSSize,
    styleMask: NSWindow.StyleMask,
    rootView: @autoclosure () -> V
) {
    if let window {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return
    }
    let w = CloseableWindow(contentViewController: NSHostingController(rootView: rootView()))
    w.title = title
    w.styleMask = styleMask
    w.isReleasedWhenClosed = false
    w.setContentSize(size)
    w.center()
    window = w
    NSApp.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
}

@MainActor
final class AboutWindow {
    private var window: NSWindow?
    private let changelog = ChangelogWindow()

    func show() {
        presentSingleton(
            &window,
            title: "About uSwitch",
            size: NSSize(width: 360, height: 440),
            styleMask: [.titled, .closable],
            rootView: AboutPane(onShowChangelog: { [weak self] in self?.changelog.show() })
        )
    }
}

@MainActor
final class ChangelogWindow {
    private var window: NSWindow?

    func show() {
        presentSingleton(
            &window,
            title: "Changelog",
            size: NSSize(width: 460, height: 560),
            styleMask: [.titled, .closable, .resizable],
            rootView: ChangelogView(releases: parseChangelog())
        )
    }
}

private var versionString: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String
    return short.map { "v\($0)" } ?? "dev"
}

private struct AboutPane: View {
    let onShowChangelog: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }
            VStack(spacing: 4) {
                Text("uSwitch")
                    .font(.system(size: 22, weight: .semibold))
                Text(versionString)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Text("Cmd+Tab replacement for macOS with live window thumbnails.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 8) {
                Link("GitHub Repository", destination: repoURL)
                Link("Report an Issue", destination: issuesURL)
            }
            .font(.system(size: 13))

            Spacer()

            Button("Changelog", action: onShowChangelog)
                .keyboardShortcut(.defaultAction)

            Text("© \(currentYear) NH")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 360, height: 440)
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }
}

// MARK: - Changelog

private struct Release: Identifiable {
    let id = UUID()
    let heading: String
    var sections: [Section]
}

private struct Section: Identifiable {
    let id = UUID()
    let title: String
    var bullets: [String]
}

private func parseChangelog() -> [Release] {
    guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
          let text = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }

    var releases: [Release] = []
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        if line.hasPrefix("## ") {
            releases.append(Release(heading: String(line.dropFirst(3)), sections: []))
        } else if line.hasPrefix("### ") {
            guard !releases.isEmpty else { continue }
            releases[releases.count - 1].sections.append(
                Section(title: String(line.dropFirst(4)), bullets: [])
            )
        } else if line.hasPrefix("- "),
                  let r = releases.indices.last,
                  let s = releases[r].sections.indices.last {
            releases[r].sections[s].bullets.append(String(line.dropFirst(2)))
        }
    }
    return releases
}

private struct ChangelogView: View {
    let releases: [Release]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if releases.isEmpty {
                    Text("Changelog not available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(releases) { release in
                        ReleaseBlock(release: release)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(minWidth: 380, minHeight: 320)
    }
}

private struct ReleaseBlock: View {
    let release: Release

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(release.heading)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            ForEach(release.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(bullet)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
