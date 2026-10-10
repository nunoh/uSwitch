import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var checksAutomatically: Bool
    @Published private(set) var downloadsAutomatically: Bool
    @Published private(set) var receivesBetas: Bool

    private let feed = FeedSelector()
    private let controller: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: feed,
            userDriverDelegate: nil
        )
        let updater = controller.updater

        // Preserve the existing daily-check choice, then let Sparkle own it.
        let defaults = UserDefaults.standard
        if let oldValue = defaults.object(forKey: "checkForUpdates") as? Bool {
            updater.automaticallyChecksForUpdates = oldValue
            defaults.removeObject(forKey: "checkForUpdates")
        }

        receivesBetas = FeedSelector.receivesBetas
        checksAutomatically = updater.automaticallyChecksForUpdates
        downloadsAutomatically = updater.automaticallyDownloadsUpdates
        observations = [
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.checksAutomatically = updater.automaticallyChecksForUpdates }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.downloadsAutomatically = updater.automaticallyDownloadsUpdates }
            },
        ]
    }

    private var isReleaseBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String != "dev"
    }

    var canCheckForUpdates: Bool { isReleaseBuild && controller.updater.canCheckForUpdates }

    func start() {
        guard isReleaseBuild else { return }
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        checksAutomatically = enabled
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
        downloadsAutomatically = enabled
    }

    func setReceivesBetas(_ enabled: Bool) {
        FeedSelector.receivesBetas = enabled
        receivesBetas = enabled
        if isReleaseBuild { controller.updater.resetUpdateCycleAfterShortDelay() }
    }
}

// Picks the stable or beta appcast. Beta builds share the stable build-number
// order, so turning betas off keeps the current build until a newer stable.
private final class FeedSelector: NSObject, SPUUpdaterDelegate {
    private static let key = "receiveBetaUpdates"
    private static let betaFeed = "https://github.com/nunoh/uSwitch/releases/download/beta/appcast.xml"

    // A beta build keeps getting betas until the user opts out.
    static var receivesBetas: Bool {
        get {
            if let value = UserDefaults.standard.object(forKey: key) as? Bool { return value }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            return version?.contains("-beta.") ?? false
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    // nil falls back to SUFeedURL, the stable feed.
    func feedURLString(for updater: SPUUpdater) -> String? {
        Self.receivesBetas ? Self.betaFeed : nil
    }
}
