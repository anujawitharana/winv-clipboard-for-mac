import AppKit
import Foundation

func createBaseImage() -> NSImage {
    let size = CGSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Standard macOS App Icon squircle (inset by 90pt for drop shadow margin)
    let rect = CGRect(x: 90, y: 90, width: 844, height: 844)
    let path = NSBezierPath(roundedRect: rect, xRadius: 195, yRadius: 195)

    // Soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 36, color: CGColor(srgbRed: 0.0, green: 0.2, blue: 0.6, alpha: 0.35))
    NSColor.black.withAlphaComponent(0.01).setFill()
    path.fill()
    ctx.restoreGState()

    // Vibrant blue gradient fill
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let startColor = CGColor(srgbRed: 0.05, green: 0.45, blue: 1.0, alpha: 1.0)
    let endColor = CGColor(srgbRed: 0.02, green: 0.68, blue: 0.98, alpha: 1.0)
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [startColor, endColor] as CFArray, locations: [0.0, 1.0])!

    ctx.saveGState()
    path.addClip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 90, y: 934), end: CGPoint(x: 934, y: 90), options: [])

    // Subtle inner border highlight
    ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.22))
    ctx.setLineWidth(4.0)
    path.stroke()
    ctx.restoreGState()

    // SF Symbol: doc.on.clipboard.fill in crisp white with subtle drop shadow
    if let symbol = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: 450, weight: .semibold)
            .applying(.init(paletteColors: [.white, NSColor(white: 1.0, alpha: 0.9)]))
        if let configured = symbol.withSymbolConfiguration(config) {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 16, color: CGColor(srgbRed: 0.0, green: 0.15, blue: 0.4, alpha: 0.3))
            let symbolSize: CGFloat = 460
            let symbolRect = CGRect(
                x: (1024 - symbolSize) / 2,
                y: (1024 - symbolSize) / 2 - 12,
                width: symbolSize,
                height: symbolSize
            )
            configured.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            ctx.restoreGState()
        }
    }

    image.unlockFocus()
    return image
}

func resizedImage(_ source: NSImage, targetSize: CGSize) -> NSImage {
    let result = NSImage(size: targetSize)
    result.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: CGRect(origin: .zero, size: targetSize), from: CGRect(origin: .zero, size: source.size), operation: .copy, fraction: 1.0)
    result.unlockFocus()
    return result
}

func savePNG(_ image: NSImage, url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        return
    }
    try? png.write(to: url)
}

let fileManager = FileManager.default
let iconsetDir = URL(fileURLWithPath: "/tmp/WinVClipboard.iconset")
try? fileManager.removeItem(at: iconsetDir)
try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let baseImage = createBaseImage()

let iconSizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, dimension) in iconSizes {
    let target = CGSize(width: dimension, height: dimension)
    let scaled = resizedImage(baseImage, targetSize: target)
    savePNG(scaled, url: iconsetDir.appendingPathComponent(name))
}

print("Iconset created at: \(iconsetDir.path)")
