import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }

    // Whether this process can capture windows. macOS only applies a new
    // Screen Recording grant after a relaunch, so this stays false until then.
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    // Whether Screen Recording is switched on in System Settings, even if this
    // process has not picked it up yet. Without the grant, other apps' window
    // titles are hidden from CGWindowList, so a readable title means granted.
    static var screenRecordingGranted: Bool {
        if screenRecording { return true }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let me = getpid()
        return list.contains { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) != me
                && (info[kCGWindowLayer as String] as? Int) == 0
                && (info[kCGWindowOwnerName as String] as? String) != "Dock"
                && !((info[kCGWindowName as String] as? String) ?? "").isEmpty
        }
    }

    // The first request shows the system prompt, which also adds uSwitch to
    // the list in System Settings. Later requests show nothing, so open the
    // right Settings pane instead.
    static func requestAccessibility() {
        if askedBefore(Key.accessibility) {
            openSettings("Privacy_Accessibility")
        } else {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
    }

    static func requestScreenRecording() {
        if askedBefore(Key.screenRecording) {
            openSettings("Privacy_ScreenCapture")
        } else {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            if let error { print("relaunch failed: \(error.localizedDescription)") }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private enum Key {
        static let accessibility = "askedForAccessibility"
        static let screenRecording = "askedForScreenRecording"
    }

    // Returns whether the prompt was shown before, and records that it has now.
    private static func askedBefore(_ key: String) -> Bool {
        let defaults = UserDefaults.standard
        defer { defaults.set(true, forKey: key) }
        return defaults.bool(forKey: key)
    }

    private static func openSettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

// Shown at launch while a permission is missing: both grants in one place,
// updating live, so the user never has to relaunch just to see the next prompt.
@MainActor
final class PermissionsWindow {
    private var window: NSWindow?
    private let model = PermissionsModel()

    // `onAccessibilityGranted` starts the switcher; it returns false when the
    // event tap still cannot be installed, which needs a relaunch.
    func show(onAccessibilityGranted: @escaping () -> Bool) {
        model.onAccessibilityGranted = onAccessibilityGranted
        model.onDone = { [weak self] in self?.window?.close() }
        model.start()
        presentSingleton(
            &window,
            title: "Set Up uSwitch",
            size: NSSize(width: 460, height: 330),
            styleMask: [.titled, .closable],
            rootView: PermissionsView(model: model)
        )
    }
}

@MainActor
private final class PermissionsModel: ObservableObject {
    @Published var accessibility = Permissions.accessibility
    @Published var screenRecording = Permissions.screenRecordingGranted
    @Published var needsRelaunch = false

    var onAccessibilityGranted: (() -> Bool)?
    var onDone: (() -> Void)?
    private var timer: Timer?
    // Screen Recording was already active in this process at launch.
    private let capturing = Permissions.screenRecording

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
    }

    private func refresh() {
        let ax = Permissions.accessibility
        if ax && !accessibility {
            print("[permissions] Accessibility granted")
            if onAccessibilityGranted?() == false { needsRelaunch = true }
        }
        accessibility = ax
        screenRecording = Permissions.screenRecordingGranted
        if screenRecording && !capturing { needsRelaunch = true }
        if accessibility && screenRecording && !needsRelaunch {
            timer?.invalidate()
            onDone?()
        }
    }
}

private struct PermissionsView: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("uSwitch needs two permissions. Turn them on in System Settings; this window updates as you go.")
                .fixedSize(horizontal: false, vertical: true)

            PermissionRow(
                title: "Accessibility",
                detail: "Detects the shortcut and switches windows.",
                symbol: "keyboard",
                granted: model.accessibility,
                action: Permissions.requestAccessibility
            )
            PermissionRow(
                title: "Screen Recording",
                detail: "Shows live window thumbnails.",
                symbol: "rectangle.on.rectangle",
                granted: model.screenRecording,
                action: Permissions.requestScreenRecording
            )

            Spacer(minLength: 0)

            HStack {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if model.needsRelaunch {
                    Button("Restart uSwitch", action: Permissions.relaunch)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460, height: 330, alignment: .topLeading)
    }

    private var footnote: String {
        if model.needsRelaunch { return "macOS applies Screen Recording after a restart." }
        if !model.accessibility { return "The switcher starts as soon as Accessibility is on." }
        return "Without Screen Recording, tiles show app icons only."
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 32)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("On", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings…", action: action)
            }
        }
    }
}
