import AppKit

// Renders the DMG window background (660x400 pt at 2x) with a dark gradient,
// the app name, an install hint, and an arrow between the two icon positions.
// Run: swift Tools/GenerateDMGBackground.swift

let pointSize = NSSize(width: 660, height: 400)
let scale: CGFloat = 2
let pixelSize = NSSize(width: pointSize.width * scale, height: pointSize.height * scale)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(pixelSize.width),
    pixelsHigh: Int(pixelSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("could not create bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext
context.scaleBy(x: scale, y: scale)

let bounds = NSRect(origin: .zero, size: pointSize)

// Background: deep night gradient.
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.14, alpha: 1),
    NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.09, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.04, alpha: 1)
])
gradient?.draw(in: bounds, angle: -90)

// Soft glow behind the title (oval so there is no hard edge).
let glow = NSGradient(
    starting: NSColor(calibratedRed: 0.45, green: 0.35, blue: 0.9, alpha: 0.22),
    ending: NSColor(calibratedRed: 0.45, green: 0.35, blue: 0.9, alpha: 0)
)
let glowPath = NSBezierPath(ovalIn: NSRect(x: 80, y: 220, width: 500, height: 230))
glow?.draw(in: glowPath, relativeCenterPosition: .zero)

// Title.
let title = "Luma" as NSString
title.draw(
    at: NSPoint(x: 330 - 62, y: 318),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 44, weight: .bold),
        .foregroundColor: NSColor.white
    ]
)

// Subtitle.
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.55)
]
let subtitle = "Drag Luma into Applications to install" as NSString
let subtitleWidth = subtitle.size(withAttributes: subtitleAttributes).width
subtitle.draw(at: NSPoint(x: 330 - subtitleWidth / 2, y: 292), withAttributes: subtitleAttributes)

// Arrow between the icon slots (icons sit at x=165 and x=495, y ~ 185).
let arrowColor = NSColor.white.withAlphaComponent(0.35)
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 265, y: 185))
arrow.line(to: NSPoint(x: 385, y: 185))
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrowColor.setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 368, y: 202))
head.line(to: NSPoint(x: 392, y: 185))
head.line(to: NSPoint(x: 368, y: 168))
head.lineWidth = 5
head.lineCapStyle = .round
head.lineJoinStyle = .round
arrowColor.setStroke()
head.stroke()

// Footer hint.
let footerAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11, weight: .regular),
    .foregroundColor: NSColor.white.withAlphaComponent(0.3)
]
let footer = "First launch: right-click Luma and choose Open" as NSString
let footerWidth = footer.size(withAttributes: footerAttributes).width
footer.draw(at: NSPoint(x: 330 - footerWidth / 2, y: 24), withAttributes: footerAttributes)

NSGraphicsContext.restoreGraphicsState()

// Mark as 144 DPI so Finder renders it at point size (retina-crisp).
rep.size = pointSize

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode png")
}
let output = URL(fileURLWithPath: "scripts/dmg-background.png")
try! png.write(to: output)
print("wrote \(output.path) (\(Int(pixelSize.width))x\(Int(pixelSize.height)) px at 2x)")
