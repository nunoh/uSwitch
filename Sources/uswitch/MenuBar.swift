import AppKit
import ServiceManagement

@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private let about = AboutWindow()
    private let settings = SettingsWindow()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle",
                accessibilityDescription: "uSwitch"
            )
        }
        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(settingsMenuItem),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        menu.addItem(launchAtLogin)
        launchAtLoginItem = launchAtLogin

        let aboutItem = NSMenuItem(
            title: "About uSwitch",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quit = NSMenuItem(
            title: "Quit uSwitch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        self.item = item
    }

    @objc private func showAbout() {
        about.show()
    }

    @objc private func settingsMenuItem() {
        settings.show()
    }

    // Also reachable from the switcher (Cmd+, while the overlay is open).
    func showSettings() {
        settings.show()
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            // .requiresApproval surfaces here on first register — macOS opens
            // the Login Items pane on its own, so just log and move on.
            print("launch-at-login toggle failed: \(error.localizedDescription) (status=\(service.status.rawValue))")
        }
    }
}
