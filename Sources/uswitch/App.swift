import AppKit
import Combine

@main
@MainActor
enum App {
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Diagnose.run()
            exit(0)
        }

        // Set this before permission checks so a directly launched executable
        // behaves like the LSUIElement app bundle from its very first frame.
        NSApplication.shared.setActivationPolicy(.accessory)
        menuBar.install()
        UpdateChecker.shared.start()

        setUp()
        // Without Accessibility the event tap cannot be installed; the setup
        // window installs it the moment it is granted, no relaunch.
        if Permissions.accessibility {
            _ = installTap()
        } else {
            print("⚠️  Accessibility not granted — waiting in the setup window.")
        }
        if !Permissions.accessibility || !Permissions.screenRecording {
            if !Permissions.screenRecording {
                print("⚠️  Screen Recording not granted — thumbnails will be blank.")
            }
            showSetup()
        }
        observeTrustChanges()

        NSApplication.shared.run()
    }

    private static let menuBar = MenuBar()
    private static let permissionsWindow = PermissionsWindow()
    private static var tap: EventTap?
    private static var switcher: Switcher?
    private static var cancellables = Set<AnyCancellable>()
    private static var trustObserver: NSObjectProtocol?

    // Build the switcher and its event tap once. The tap is installed
    // separately, and again after Accessibility comes back.
    private static func setUp() {
        let settings = Settings.shared
        let menuBar = self.menuBar
        let cache = ThumbnailCache()
        cache.startObserving()
        Spaces.startObserving()
        let switcher = Switcher(cache: cache)
        let tap = EventTap()
        tap.isActive  = { MainActor.assumeIsolated { switcher.isOpen } }
        tap.onTrigger = { MainActor.assumeIsolated { switcher.open() } }
        tap.onTriggerOverview = { MainActor.assumeIsolated { switcher.openOverview() } }
        tap.onCycle   = { backward in MainActor.assumeIsolated { switcher.cycle(backward: backward) } }
        tap.onEscape  = { MainActor.assumeIsolated { switcher.close() } }
        tap.onCommit  = { MainActor.assumeIsolated { switcher.commit() } }
        tap.onQuit    = { MainActor.assumeIsolated { switcher.quitSelected() } }
        tap.onCloseWindow = { MainActor.assumeIsolated { switcher.closeSelectedWindow() } }
        tap.onMinimize = { MainActor.assumeIsolated { switcher.minimizeSelected() } }
        tap.onToggleMode = { MainActor.assumeIsolated { switcher.toggleMode() } }
        tap.onSettings = { MainActor.assumeIsolated {
            // Bail out of the switcher without switching, then show Settings.
            switcher.close()
            menuBar.showSettings()
        } }
        tap.isSuspended = { HotkeyRecorder.isRecording }
        tap.onTrustRevoked = { MainActor.assumeIsolated { trustRevoked() } }

        // Keep the tap's shortcuts in sync with settings, live.
        tap.primaryHotkey = settings.primaryHotkey
        tap.overviewHotkey = settings.overviewHotkey
        settings.$primaryHotkey.sink { tap.primaryHotkey = $0 }.store(in: &cancellables)
        settings.$overviewHotkey.sink { tap.overviewHotkey = $0 }.store(in: &cancellables)

        self.tap = tap
        self.switcher = switcher
    }

    // Returns false when the tap cannot be installed yet (Accessibility
    // missing or not applied to this process).
    private static func installTap() -> Bool {
        guard let tap else { return false }
        if tap.isInstalled { return true }
        print("uswitch — installing event tap…")
        guard tap.install() else {
            print("⚠️  Failed to install event tap. Try toggling Accessibility off/on for this binary.")
            return false
        }

        let settings = Settings.shared
        print("✅ Ready.")
        print("   \(settings.primaryHotkey.displayString) — open / cycle forward")
        print("   +Shift — backward")
        print("   \(settings.overviewHotkey.displayString) — all-Spaces overview")
        print("   Esc — cancel (swallowed, will not reach iTerm)")
        print("   Cmd+Q / Cmd+W / Cmd+M — quit / close / minimize the selected window")
        print("   S / Cmd+F (while open) — toggle the all-Spaces overview")
        print("   Cmd+, (while open) — open Settings")
        print("   Release the modifier — switch to the selected window")
        print("   Settings — menu bar icon → Settings…\n")
        return true
    }

    private static func showSetup() {
        permissionsWindow.show(onAccessibilityGranted: { installTap() })
    }

    // A live event tap without Accessibility can freeze all input (seen when
    // `tccutil reset` runs under a running uSwitch), so remove it as soon as
    // the grant disappears instead of waiting for the tap to time out.
    // macOS posts this (undocumented) notification whenever any app's
    // Accessibility grant changes; if it ever stops, the tap still removes
    // itself when macOS disables it (EventTap.handle).
    private static func observeTrustChanges() {
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { _ in
            // The trust check can lag the notification briefly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    guard tap?.isInstalled == true, !AXIsProcessTrusted() else { return }
                    print("⚠️  Accessibility revoked — removing the event tap.")
                    trustRevoked()
                }
            }
        }
    }

    private static func trustRevoked() {
        tap?.uninstall()
        switcher?.close()
        showSetup()
    }
}
