import AppKit
import Foundation

// Builds the Luma app icon from Tools/AppIconSource.png. If the source is a
// pre-shaped icon on a solid canvas (a rounded tile with a margin), the margin
// is auto-detected and cropped; the tile is then masked into the native macOS
// squircle with transparent corners. Full-bleed art is used as-is.
//
//   swift Tools/GenerateIcon.swift

let source = "Tools/AppIconSource.png"
let iconsetDir = "Luma/Resources/Assets.xcassets/AppIcon.appiconset"
let logoPath = "Luma-Logo-1024.png"

guard let loaded = NSImage(contentsOfFile: source),
      let tiff = loaded.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let fullCG = rep.cgImage else {
    FileHandle.standardError.write(Data("Cannot load \(source)\n".utf8))
    exit(1)
}

let width = rep.pixelsWide
let height = rep.pixelsHigh

func components(_ x: Int, _ y: Int) -> (CGFloat, CGFloat, CGFloat)? {
    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return nil }
    return (color.redComponent, color.greenComponent, color.blueComponent)
}

func distance(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
    abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)
}

// Detect the content tile by scanning the middle row/column against the canvas
// colour (sampled from a corner). Middle lines cross the tile's straight edges.
func contentSquare() -> CGRect {
    guard let background = components(2, 2) else {
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
    let tolerance: CGFloat = 0.14
    let midY = height / 2
    let midX = width / 2

    func firstContent(_ range: StrideThrough<Int>, horizontal: Bool) -> Int? {
        for i in range {
            let sample = horizontal ? components(i, midY) : components(midX, i)
            if let sample, distance(sample, background) > tolerance { return i }
        }
        return nil
    }

    let minX = firstContent(stride(from: 0, through: width - 1, by: 1), horizontal: true) ?? 0
    let maxX = firstContent(stride(from: width - 1, through: 0, by: -1), horizontal: true) ?? (width - 1)
    let minY = firstContent(stride(from: 0, through: height - 1, by: 1), horizontal: false) ?? 0
    let maxY = firstContent(stride(from: height - 1, through: 0, by: -1), horizontal: false) ?? (height - 1)

    let w = maxX - minX
    let h = maxY - minY
    // If detection failed or covers almost everything, use the full image.
    guard w > 0, h > 0, w < Int(Double(width) * 0.98) else {
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    let side = max(w, h)
    let cx = (minX + maxX) / 2
    let cy = (minY + maxY) / 2
    let originX = max(0, cx - side / 2)
    let originY = max(0, cy - side / 2)
    let clampedSide = min(side, min(width - originX, height - originY))
    return CGRect(x: originX, y: originY, width: clampedSide, height: clampedSide)
}

let crop = contentSquare()
let croppedCG = fullCG.cropping(to: crop) ?? fullCG
let tile = NSImage(cgImage: croppedCG, size: NSSize(width: crop.width, height: crop.height))

func render(_ s: CGFloat) -> Data? {
    guard let out = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    out.size = NSSize(width: s, height: s)

    guard let ctx = NSGraphicsContext(bitmapImageRep: out) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: s, height: s))

    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let radius = s * 0.2237
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    tile.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return out.representation(using: .png, properties: [:])
}

let outputs: [(CGFloat, [String])] = [
    (16, ["icon_16x16.png"]),
    (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64, ["icon_32x32@2x.png"]),
    (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"])
]

let fileManager = FileManager.default
for (size, names) in outputs {
    guard let data = render(size) else {
        FileHandle.standardError.write(Data("Failed to render \(size)\n".utf8))
        exit(1)
    }
    for name in names {
        fileManager.createFile(atPath: "\(iconsetDir)/\(name)", contents: data)
    }
    if size == 1024 {
        fileManager.createFile(atPath: logoPath, contents: data)
    }
    print("rendered \(Int(size))px")
}
print("done  (crop: \(Int(crop.width))×\(Int(crop.height)) of \(width)×\(height))")
