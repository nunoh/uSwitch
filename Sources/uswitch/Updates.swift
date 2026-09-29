import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var checksAutomatically: Bool
    @Published private(set) var downloadsAutomatically: Bool

    private let controller: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let updater = controller.updater

        // Preserve the existing daily-check choice, then let Sparkle own it.
        let defaults = UserDefaults.standard
        if let oldValue = defaults.object(forKey: "checkForUpdates") as? Bool {
            updater.automaticallyChecksForUpdates = oldValue
            defaults.removeObject(forKey: "checkForUpdates")
        }

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
}
