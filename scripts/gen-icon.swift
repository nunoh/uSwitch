import AppKit

let out = "Resources/AppIcon.icns"
let symbolName = "rectangle.on.rectangle"

func render(_ size: CGFloat) -> Data {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    defer { img.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.30, green: 0.40, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.25, blue: 0.85, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: 270)

    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else {
        fatalError("symbol \(symbolName) not found")
    }

    let s = symbol.size
    let scale = (size * 0.55) / max(s.width, s.height)
    let drawSize = NSSize(width: s.width * scale, height: s.height * scale)
    let origin = NSPoint(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2)
    symbol.draw(in: NSRect(origin: origin, size: drawSize))

    let cg = NSBitmapImageRep(focusedViewRect: rect)!
    return cg.representation(using: .png, properties: [:])!
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let tmp = "/tmp/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: tmp)
try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)

for (name, size) in sizes {
    let data = render(size)
    try! data.write(to: URL(fileURLWithPath: "\(tmp)/\(name)"))
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", tmp, "-o", out]
try! task.run()
task.waitUntilExit()

print("✅ wrote \(out)")
