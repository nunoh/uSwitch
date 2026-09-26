import AppKit
import Combine
import CoreGraphics

// A keyboard shortcut: a trigger key plus the modifiers held with it.
struct Hotkey: Equatable {
    var keyCode: CGKeyCode
    var modifiers: CGEventFlags  // command / option / control / shift only
    var label: String

    static let primaryDefault = Hotkey(keyCode: 48, modifiers: [.maskCommand], label: "⇥")
    static let overviewDefault = Hotkey(keyCode: 48, modifiers: [.maskAlternate], label: "⇥")

    static let relevantModifiers: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift,
    ]

    var normalizedModifiers: CGEventFlags {
        modifiers.intersection(Self.relevantModifiers)
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.maskControl) { parts.append("⌃") }
        if modifiers.contains(.maskAlternate) { parts.append("⌥") }
        if modifiers.contains(.maskShift) { parts.append("⇧") }
        if modifiers.contains(.maskCommand) { parts.append("⌘") }
        parts.append(label.isEmpty ? Self.keyName(keyCode) : label)
        return parts.joined()
    }

    // The modifiers that must be released to commit a switch. Shift is excluded:
    // it only selects direction.
    var commitModifiers: CGEventFlags {
        normalizedModifiers.intersection([.maskCommand, .maskAlternate, .maskControl])
    }

    func matches(_ keyCode: CGKeyCode, _ flags: CGEventFlags) -> Bool {
        guard keyCode == self.keyCode else { return false }
        let relevant = flags.intersection(Self.relevantModifiers)
        if relevant == normalizedModifiers { return true }
        // Shift is accepted as an extra modifier so Shift+hotkey goes backward.
        if !normalizedModifiers.contains(.maskShift) {
            return relevant == normalizedModifiers.union(.maskShift)
        }
        return false
    }

    func isReleased(_ flags: CGEventFlags) -> Bool {
        let held = flags.intersection(Self.relevantModifiers)
        return !commitModifiers.isSubset(of: held)
    }

    // Build a shortcut from a recorded key event. Requires at least one
    // modifier so a plain key press cannot become a global shortcut.
    static func from(_ event: NSEvent) -> Hotkey? {
        let modifiers = cgModifiers(from: event.modifierFlags)
        guard !modifiers.isEmpty else { return nil }
        let label: String
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty,
           chars.rangeOfCharacter(from: .controlCharacters) == nil {
            label = chars.uppercased()
        } else {
            label = keyName(CGKeyCode(event.keyCode))
        }
        return Hotkey(keyCode: CGKeyCode(event.keyCode), modifiers: modifiers, label: label)
    }

    static func cgModifiers(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        return result
    }

    private static let keyNames: [CGKeyCode: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
        50: "`", 51: "⌫", 53: "⎋", 36: "↩", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func keyName(_ keyCode: CGKeyCode) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }
}

// Set while the settings window is capturing a shortcut, so the event tap lets
// every key through instead of swallowing global shortcuts.
enum HotkeyRecorder {
    nonisolated(unsafe) static var isRecording = false
}

struct TileMetrics {
    var width: CGFloat
    var height: CGFloat
    var icon: CGFloat
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    enum TileSize: String, CaseIterable, Identifiable {
        case small, medium, large

        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        var width: CGFloat {
            switch self {
            case .small: return 150
            case .medium: return 180
            case .large: return 210
            }
        }
        var height: CGFloat { (width * 2 / 3).rounded() }
        var icon: CGFloat { (width * 0.31).rounded() }
        var metrics: TileMetrics { TileMetrics(width: width, height: height, icon: icon) }
    }

    @Published var primaryHotkey: Hotkey { didSet { persist() } }
    @Published var overviewHotkey: Hotkey { didSet { persist() } }
    @Published var minimizedShown: Bool { didSet { persist() } }
    @Published var minimizedInCycle: Bool { didSet { persist() } }
    @Published var tileSize: TileSize { didSet { persist() } }
    @Published var otherSpaceScale: Double { didSet { persist() } }
    @Published var flickDelay: Double { didSet { persist() } }
    @Published var checkForUpdates: Bool { didSet { persist() } }

    private let defaults = UserDefaults.standard
    private var isLoading = true

    private init() {
        primaryHotkey = .primaryDefault
        overviewHotkey = .overviewDefault
        minimizedShown = true
        minimizedInCycle = false
        tileSize = .medium
        otherSpaceScale = 0.72
        // No flick grace by default: the overlay shows on every switch, as it
        // did before this was configurable.
        flickDelay = 0
        checkForUpdates = true
        load()
        isLoading = false
    }

    func resetToDefaults() {
        primaryHotkey = .primaryDefault
        overviewHotkey = .overviewDefault
        minimizedShown = true
        minimizedInCycle = false
        tileSize = .medium
        otherSpaceScale = 0.72
        flickDelay = 0
        checkForUpdates = true
    }

    // MARK: - Persistence

    private enum Key {
        static let primary = "primaryHotkey"
        static let overview = "overviewHotkey"
        static let minimizedShown = "minimizedShown"
        static let minimizedInCycle = "minimizedInCycle"
        static let tileSize = "tileSize"
        static let otherSpaceScale = "otherSpaceScale"
        // Renamed from "flickDelay" so the pre-0 default (0.1s) does not linger.
        static let flickDelay = "flickDelaySeconds"
        static let checkForUpdates = "checkForUpdates"
    }

    private func load() {
        if let hotkey = readHotkey(Key.primary) { primaryHotkey = hotkey }
        if let hotkey = readHotkey(Key.overview) { overviewHotkey = hotkey }
        if defaults.object(forKey: Key.minimizedShown) != nil {
            minimizedShown = defaults.bool(forKey: Key.minimizedShown)
        }
        if defaults.object(forKey: Key.minimizedInCycle) != nil {
            minimizedInCycle = defaults.bool(forKey: Key.minimizedInCycle)
        }
        if let raw = defaults.string(forKey: Key.tileSize), let size = TileSize(rawValue: raw) {
            tileSize = size
        }
        if defaults.object(forKey: Key.otherSpaceScale) != nil {
            otherSpaceScale = defaults.double(forKey: Key.otherSpaceScale)
        }
        if defaults.object(forKey: Key.flickDelay) != nil {
            flickDelay = defaults.double(forKey: Key.flickDelay)
        }
        if defaults.object(forKey: Key.checkForUpdates) != nil {
            checkForUpdates = defaults.bool(forKey: Key.checkForUpdates)
        }
    }

    private func persist() {
        guard !isLoading else { return }
        writeHotkey(primaryHotkey, Key.primary)
        writeHotkey(overviewHotkey, Key.overview)
        defaults.set(minimizedShown, forKey: Key.minimizedShown)
        defaults.set(minimizedInCycle, forKey: Key.minimizedInCycle)
        defaults.set(tileSize.rawValue, forKey: Key.tileSize)
        defaults.set(otherSpaceScale, forKey: Key.otherSpaceScale)
        defaults.set(flickDelay, forKey: Key.flickDelay)
        defaults.set(checkForUpdates, forKey: Key.checkForUpdates)
    }

    private func readHotkey(_ key: String) -> Hotkey? {
        guard let dict = defaults.dictionary(forKey: key),
              let keyCode = dict["keyCode"] as? Int,
              let raw = dict["modifiers"] as? UInt64
        else { return nil }
        return Hotkey(
            keyCode: CGKeyCode(keyCode),
            modifiers: CGEventFlags(rawValue: raw),
            label: dict["label"] as? String ?? ""
        )
    }

    private func writeHotkey(_ hotkey: Hotkey, _ key: String) {
        defaults.set([
            "keyCode": Int(hotkey.keyCode),
            "modifiers": hotkey.normalizedModifiers.rawValue,
            "label": hotkey.label,
        ], forKey: key)
    }
}
