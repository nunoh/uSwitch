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

        print("uswitch v0.1 — installing event tap…")

        // Set this before permission checks so a directly launched executable
        // behaves like the LSUIElement app bundle from its very first frame.
        NSApplication.shared.setActivationPolicy(.accessory)

        guard ensureAccessibility() else {
            print("⚠️  Grant Accessibility permission and re-run.")
            exit(1)
        }

        if !ensureScreenRecording() {
            print("⚠️  Screen Recording permission not granted — thumbnails will be blank.")
            print("    Grant it in System Settings → Privacy & Security → Screen Recording, then re-run.")
        }

        let settings = Settings.shared
        let menuBar = MenuBar()
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
        tap.onSettings = { MainActor.assumeIsolated {
            // Bail out of the switcher without switching, then show Settings.
            switcher.close()
            menuBar.showSettings()
        } }
        tap.isSuspended = { HotkeyRecorder.isRecording }

        // Keep the tap's shortcuts in sync with settings, live.
        tap.primaryHotkey = settings.primaryHotkey
        tap.overviewHotkey = settings.overviewHotkey
        var cancellables = Set<AnyCancellable>()
        settings.$primaryHotkey.sink { tap.primaryHotkey = $0 }.store(in: &cancellables)
        settings.$overviewHotkey.sink { tap.overviewHotkey = $0 }.store(in: &cancellables)

        guard tap.install() else {
            print("⚠️  Failed to install event tap. Try toggling Accessibility off/on for this binary.")
            exit(1)
        }

        print("✅ Ready.")
        print("   \(settings.primaryHotkey.displayString) — open / cycle forward")
        print("   +Shift — backward")
        print("   \(settings.overviewHotkey.displayString) — all-Spaces overview")
        print("   Esc — cancel (swallowed, will not reach iTerm)")
        print("   Cmd+Q / Cmd+W / Cmd+M — quit / close / minimize the selected window")
        print("   Cmd+, (while open) — open Settings")
        print("   Release the modifier — switch to the selected window")
        print("   Settings — menu bar icon → Settings…\n")

        menuBar.install()
        NSApplication.shared.run()
        _ = menuBar  // retain
    }
}
