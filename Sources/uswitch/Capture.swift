import AppKit
import CoreGraphics

enum Capture {
    static func snapshot(of windowID: CGWindowID) -> NSImage? {
        guard let cg = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
