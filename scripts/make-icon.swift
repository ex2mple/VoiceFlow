// Generates AppIcon.icns: dark rounded square with equalizer bars —
// the same wave the HUD shows. Run via `make icon` (swift scripts/make-icon.swift).
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconsetURL = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func drawIcon(_ pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels)
    // macOS icon grid: the squircle occupies ~80% of the canvas.
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1))!
    gradient.draw(in: squircle, angle: -90)

    // Equalizer bars, mirroring the HUD's bell envelope.
    let heights: [CGFloat] = [0.22, 0.38, 0.60, 0.82, 0.95, 0.82, 0.60, 0.38, 0.22]
    let n = heights.count
    let barWidth = rect.width * 0.055
    let gap = (rect.width * 0.72 - CGFloat(n) * barWidth) / CGFloat(n - 1)
    let startX = rect.midX - (CGFloat(n) * barWidth + CGFloat(n - 1) * gap) / 2
    let maxBar = rect.height * 0.52

    for (i, h) in heights.enumerated() {
        let height = maxBar * h
        let bar = NSRect(
            x: startX + CGFloat(i) * (barWidth + gap),
            y: rect.midY - height / 2,
            width: barWidth, height: height)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for size in sizes {
    let rep = drawIcon(size)
    let png = rep.representation(using: .png, properties: [:])!
    let base = size == 1024 ? 512 : size
    let suffix = size == 1024 ? "512x512@2x" : "\(base)x\(base)"
    try png.write(to: iconsetURL.appendingPathComponent("icon_\(suffix).png"))
    if size >= 32 && size <= 512 {
        try png.write(to: iconsetURL.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png"))
    }
}
print("iconset written to \(iconsetURL.path)")
