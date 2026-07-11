import AppKit

@main
@MainActor
enum App {
    static func main() {
        print("uswitch v0.1 — installing event tap…")

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

        guard tap.install() else {
            print("⚠️  Failed to install event tap. Try toggling Accessibility off/on for this binary.")
            exit(1)
        }

        print("✅ Ready.")
        print("   Cmd+Tab — open / cycle forward")
        print("   Cmd+Shift+Tab — backward")
        print("   Esc — cancel (swallowed, will not reach iTerm)")
        print("   Release Cmd — switch to selected window")
        print("   Click a tile — switch to that window directly")
        print("   Quit via menu bar icon, or Ctrl+C\n")

        NSApplication.shared.setActivationPolicy(.accessory)
        let menuBar = MenuBar()
        menuBar.install()
        NSApplication.shared.run()
        _ = menuBar  // retain
    }
}
