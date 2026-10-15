// Renders the app icon master (1024x1024 PNG) and the appiconset sizes.
// Usage: swiftc -o /tmp/make-icon scripts/make-icon.swift && /tmp/make-icon App/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let master: CGFloat = 1024

func render(side: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = side / master
    let inset = 100 * s
    let body = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.98, alpha: 1),
                        NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.70, alpha: 1)])!.draw(in: path, angle: -90)

    // White SD-card glyph.
    let config = NSImage.SymbolConfiguration(pointSize: 520 * s, weight: .regular)
    if let symbol = NSImage(systemSymbolName: "sdcard.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        let r = NSRect(x: (side - tinted.size.width) / 2, y: (side - tinted.size.height) / 2 + 10 * s,
                       width: tinted.size.width, height: tinted.size.height)
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 24 * s; shadow.shadowOffset = NSSize(width: 0, height: -10 * s); shadow.set()
        tinted.draw(in: r)
        NSGraphicsContext.current?.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(name: String, px: CGFloat, pt: String, scale: String)] = [
    ("icon_16x16.png", 16, "16x16", "1x"), ("icon_16x16@2x.png", 32, "16x16", "2x"),
    ("icon_32x32.png", 32, "32x32", "1x"), ("icon_32x32@2x.png", 64, "32x32", "2x"),
    ("icon_128x128.png", 128, "128x128", "1x"), ("icon_128x128@2x.png", 256, "128x128", "2x"),
    ("icon_256x256.png", 256, "256x256", "1x"), ("icon_256x256@2x.png", 512, "256x256", "2x"),
    ("icon_512x512.png", 512, "512x512", "1x"), ("icon_512x512@2x.png", 1024, "512x512", "2x"),
]
var images: [[String: String]] = []
for s in sizes {
    let data = render(side: s.px).representation(using: .png, properties: [:])!
    try! data.write(to: outDir.appendingPathComponent(s.name))
    images.append(["filename": s.name, "idiom": "mac", "scale": s.scale, "size": s.pt])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
print("wrote \(sizes.count) icon sizes to \(outDir.path)")
