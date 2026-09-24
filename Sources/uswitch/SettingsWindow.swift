import AppKit
import SwiftUI

@MainActor
final class SettingsWindow {
    private var window: NSWindow?

    func show() {
        presentSingleton(
            &window,
            title: "uSwitch Settings",
            size: NSSize(width: 440, height: 560),
            styleMask: [.titled, .closable],
            rootView: SettingsView(settings: .shared)
        )
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section("Shortcuts") {
                HotkeyRow(title: "Switcher (current Space)", hotkey: $settings.primaryHotkey)
                HotkeyRow(title: "All-Spaces overview", hotkey: $settings.overviewHotkey)
            }

            Section("Windows") {
                Toggle("Show minimized windows", isOn: $settings.minimizedShown)
                Toggle("Cycle through minimized windows", isOn: $settings.minimizedInCycle)
                    .disabled(!settings.minimizedShown)
            }

            Section("Appearance") {
                Picker("Thumbnail size", selection: $settings.tileSize) {
                    ForEach(Settings.TileSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                ValueSlider(
                    title: "Other Spaces size",
                    value: $settings.otherSpaceScale,
                    range: 0.5...1.0,
                    step: 0.02,
                    display: "\(Int((settings.otherSpaceScale * 100).rounded()))%"
                )
            }

            Section("Timing") {
                ValueSlider(
                    title: "Flick delay",
                    value: $settings.flickDelay,
                    range: 0...0.3,
                    step: 0.01,
                    display: String(format: "%.2fs", settings.flickDelay)
                )
                Text("A quicker tap than this switches without showing the overlay.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { settings.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 560)
    }
}

private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

// A button that turns into a shortcut recorder: click, then press the keys.
private struct HotkeyRow: View {
    let title: String
    @Binding var hotkey: Hotkey
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(recording ? "Press keys…" : hotkey.displayString) {
                recording ? stop() : start()
            }
            .frame(minWidth: 110)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotkeyRecorder.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Esc cancels without changing the shortcut.
            if event.keyCode == 53 {
                stop()
                return nil
            }
            // A shortcut needs a modifier; keep waiting for a valid one.
            if let captured = Hotkey.from(event) {
                hotkey = captured
                stop()
            }
            return nil
        }
    }

    private func stop() {
        guard recording || monitor != nil else { return }
        recording = false
        HotkeyRecorder.isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
