import AppKit

// Looks for a newer GitHub release once a day. Release builds are ad-hoc
// signed, so there is no in-place install: an update is offered as a link to
// its release page from the menu bar.
@MainActor
final class UpdateChecker {
    struct Release {
        let version: String
        let page: URL
    }

    static let shared = UpdateChecker()

    private(set) var available: Release?
    private var timer: Timer?
    private let endpoint = URL(string: "https://api.github.com/repos/nunoh/uSwitch/releases/latest")!
    private let interval: TimeInterval = 24 * 60 * 60

    // nil for dev builds ("dev"), which never look for updates on their own.
    static var currentVersion: String? {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short.flatMap { components($0) != nil ? $0 : nil }
    }

    func start() {
        guard Self.currentVersion != nil else { return }
        check(userInitiated: false)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { UpdateChecker.shared.check(userInitiated: false) }
        }
    }

    // A user-initiated check always runs and reports its result in an alert,
    // including "up to date" and failures. Background checks stay silent and
    // honour the setting.
    func check(userInitiated: Bool) {
        guard userInitiated || Settings.shared.checkForUpdates else { return }
        Task {
            let result = await fetchLatest()
            switch result {
            case .success(let latest):
                let newer = Self.isNewer(latest.version, than: Self.currentVersion ?? "0")
                available = newer ? latest : nil
                print("[updates] latest v\(latest.version), current \(Self.currentVersion ?? "dev")\(newer ? " — update available" : "")")
                if userInitiated { newer ? offer(latest) : reportUpToDate() }
            case .failure(let error):
                print("[updates] check failed: \(error.localizedDescription)")
                if userInitiated { reportFailure(error) }
            }
        }
    }

    func openAvailable() {
        guard let available else { return }
        NSWorkspace.shared.open(available.page)
    }

    private func fetchLatest() async -> Result<Release, Error> {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let payload = try JSONDecoder().decode(LatestRelease.self, from: data)
            let version = payload.tagName.hasPrefix("v") ? String(payload.tagName.dropFirst()) : payload.tagName
            guard Self.components(version) != nil, let page = URL(string: payload.htmlURL) else {
                throw URLError(.cannotParseResponse)
            }
            return .success(Release(version: version, page: page))
        } catch {
            return .failure(error)
        }
    }

    private struct LatestRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    // MARK: - Versions

    private static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = components(candidate), let b = components(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Alerts

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "uSwitch v\(release.version) is available"
        alert.informativeText = "You have v\(Self.currentVersion ?? "dev"). Download the new version from GitHub, then replace uSwitch in Applications."
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Later")
        if present(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.page)
        }
    }

    private func reportUpToDate() {
        let alert = NSAlert()
        alert.messageText = "uSwitch is up to date"
        alert.informativeText = "v\(Self.currentVersion ?? "dev") is the latest version."
        present(alert)
    }

    private func reportFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not check for updates"
        alert.informativeText = error.localizedDescription
        present(alert)
    }

    // An accessory app must come forward, or the alert opens behind other apps.
    @discardableResult
    private func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
