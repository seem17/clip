import AppKit
import CoreGraphics

func createIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.1
    let squircleRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = squircleRect.width * 0.22

    // 1. Drop shadow behind squircle
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.04),
        blur: size * 0.08,
        color: NSColor(calibratedRed: 0.05, green: 0.2, blue: 0.5, alpha: 0.45).cgColor
    )

    let path = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(path)

    // Base background gradient: Electric Royal Blue to Vivid Cyan
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        NSColor(calibratedRed: 0.12, green: 0.35, blue: 0.95, alpha: 0.95).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.65, blue: 0.95, alpha: 0.95).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 1.0])!
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
        end: CGPoint(x: squircleRect.maxX, y: squircleRect.minY),
        options: []
    )
    ctx.restoreGState()

    // 2. Liquid Glass Frost Overlay
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    // Diagonal glass sheen
    let sheenColors = [
        NSColor(white: 1.0, alpha: 0.45).cgColor,
        NSColor(white: 1.0, alpha: 0.05).cgColor,
        NSColor(white: 1.0, alpha: 0.20).cgColor
    ] as CFArray
    let sheenGradient = CGGradient(colorsSpace: colorSpace, colors: sheenColors, locations: [0.0, 0.45, 1.0])!
    ctx.drawLinearGradient(
        sheenGradient,
        start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
        end: CGPoint(x: squircleRect.maxX, y: squircleRect.minY),
        options: []
    )

    // 3. Central Paperclip Symbol
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .bold)
    if let symbol = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -size * 0.02),
            blur: size * 0.04,
            color: NSColor(white: 0.0, alpha: 0.25).cgColor
        )
        let symSize = symbol.size
        let symOrigin = CGPoint(
            x: (size - symSize.width) / 2,
            y: (size - symSize.height) / 2
        )
        symbol.draw(in: CGRect(origin: symOrigin, size: symSize), from: .zero, operation: .sourceOver, fraction: 0.98)
        ctx.restoreGState()
    }

    ctx.restoreGState()

    // 4. Liquid Glass Rim Highlight
    ctx.saveGState()
    ctx.setLineWidth(size * 0.015)
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.65).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

let fileManager = FileManager.default
let iconsetDir = URL(fileURLWithPath: "AppIcon.iconset")
try? fileManager.removeItem(at: iconsetDir)
try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

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
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    let img = createIcon(size: size)
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let dest = iconsetDir.appendingPathComponent(name)
        try? png.write(to: dest)
    }
}

print("Iconset created successfully.")
