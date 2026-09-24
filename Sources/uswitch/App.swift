import AppKit

@main
@MainActor
enum App {
    static func main() {
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

        let cache = ThumbnailCache()
        cache.startObserving()
        Spaces.startObserving()
        let switcher = Switcher(cache: cache)
        let tap = EventTap()
        tap.isActive  = { MainActor.assumeIsolated { switcher.isOpen } }
        tap.onTrigger = { MainActor.assumeIsolated { switcher.open() } }
        tap.onCycle   = { backward in MainActor.assumeIsolated { switcher.cycle(backward: backward) } }
        tap.onEscape  = { MainActor.assumeIsolated { switcher.close() } }
        tap.onCommit  = { MainActor.assumeIsolated { switcher.commit() } }
        tap.onQuit    = { MainActor.assumeIsolated { switcher.quitSelected() } }
        tap.onCloseWindow = { MainActor.assumeIsolated { switcher.closeSelectedWindow() } }
        tap.onMinimize = { MainActor.assumeIsolated { switcher.minimizeSelected() } }

        guard tap.install() else {
            print("⚠️  Failed to install event tap. Try toggling Accessibility off/on for this binary.")
            exit(1)
        }

        print("✅ Ready.")
        print("   Cmd+Tab — open / cycle forward")
        print("   Cmd+Shift+Tab — backward")
        print("   Esc — cancel (swallowed, will not reach iTerm)")
        print("   Cmd+Q — quit the selected app, stay in the overlay")
        print("   Cmd+W — close the selected window, stay in the overlay")
        print("   Cmd+M — minimize the selected window, stay in the overlay")
        print("   Release Cmd — switch to selected window")
        print("   Click a tile — switch to that window directly")
        print("   Quit via menu bar icon, or Ctrl+C\n")

        let menuBar = MenuBar()
        menuBar.install()
        NSApplication.shared.run()
        _ = menuBar  // retain
    }
}
