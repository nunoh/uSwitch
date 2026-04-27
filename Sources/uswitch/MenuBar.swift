import AppKit

@MainActor
final class MenuBar {
    private var item: NSStatusItem?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle",
                accessibilityDescription: "uswitch"
            )
        }
        let menu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit uswitch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        self.item = item
    }
}
