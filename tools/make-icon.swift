// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
// Draws kaju's app icon (a ginger cat head on a warm dark rounded square) and
// writes Resources/AppIcon.iconset. Run: swift tools/make-icon.swift && iconutil -c icns Resources/AppIcon.iconset
import AppKit

let ginger = NSColor(srgbRed: 0.929, green: 0.549, blue: 0.220, alpha: 1)
let gingerDark = NSColor(srgbRed: 0.800, green: 0.420, blue: 0.140, alpha: 1)
let cream = NSColor(srgbRed: 0.980, green: 0.800, blue: 0.580, alpha: 1)
let bgTop = NSColor(srgbRed: 0.165, green: 0.145, blue: 0.130, alpha: 1)
let bgBottom = NSColor(srgbRed: 0.090, green: 0.080, blue: 0.072, alpha: 1)
let ink = NSColor(srgbRed: 0.110, green: 0.098, blue: 0.090, alpha: 1)

/// Draw on a 1024 x 1024 canvas (macOS icon grid: 824 x 824 tile, inset 100).
func draw() {
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(starting: bgTop, ending: bgBottom)!.draw(in: squircle, angle: -90)

    // Head: a wide rounded shape with two ears, centred slightly low.
    let head = NSBezierPath()
    head.windingRule = .nonZero  // ears and head overlap; fill the union
    let cx: CGFloat = 512, cy: CGFloat = 450
    head.appendOval(in: NSRect(x: cx - 250, y: cy - 205, width: 500, height: 410))
    for side: CGFloat in [-1, 1] {
        let ear = NSBezierPath()
        ear.move(to: NSPoint(x: cx + side * 235, y: cy + 60))
        ear.line(to: NSPoint(x: cx + side * 215, y: cy + 330))
        ear.line(to: NSPoint(x: cx + side * 60, y: cy + 175))
        ear.close()
        ear.lineJoinStyle = .round
        // Mirrored ears have opposite winding; keep both the same as the head.
        head.append(side < 0 ? ear.reversed : ear)
    }
    NSGradient(starting: ginger, ending: gingerDark)!.draw(in: head, angle: -90)

    // Inner ears.
    cream.withAlphaComponent(0.55).setFill()
    for side: CGFloat in [-1, 1] {
        let inner = NSBezierPath()
        inner.move(to: NSPoint(x: cx + side * 205, y: cy + 110))
        inner.line(to: NSPoint(x: cx + side * 195, y: cy + 270))
        inner.line(to: NSPoint(x: cx + side * 100, y: cy + 175))
        inner.close()
        inner.fill()
    }

    // Eyes: content, half-closed (a cat that has just eaten).
    ink.setStroke()
    for side: CGFloat in [-1, 1] {
        let eye = NSBezierPath()
        eye.lineWidth = 26
        eye.lineCapStyle = .round
        let ex = cx + side * 105
        eye.move(to: NSPoint(x: ex - 52, y: cy + 20))
        eye.curve(to: NSPoint(x: ex + 52, y: cy + 20),
                  controlPoint1: NSPoint(x: ex - 25, y: cy - 22), controlPoint2: NSPoint(x: ex + 25, y: cy - 22))
        eye.stroke()
    }

    // Nose and a small cream speech bubble: kaju is about comments.
    cream.setFill()
    let nose = NSBezierPath()
    nose.move(to: NSPoint(x: cx - 26, y: cy - 55))
    nose.line(to: NSPoint(x: cx + 26, y: cy - 55))
    nose.line(to: NSPoint(x: cx, y: cy - 85))
    nose.close()
    nose.fill()

    let bubble = NSBezierPath(roundedRect: NSRect(x: 640, y: 175, width: 230, height: 150), xRadius: 60, yRadius: 60)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 680, y: 195))
    tail.line(to: NSPoint(x: 640, y: 150))
    tail.line(to: NSPoint(x: 720, y: 180))
    tail.close()
    bubble.append(tail)
    cream.setFill()
    bubble.fill()
    ink.setFill()
    for i in 0..<3 {
        NSBezierPath(ovalIn: NSRect(x: 690 + CGFloat(i) * 50, y: 235, width: 30, height: 30)).fill()
    }
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    NSGraphicsContext.current!.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "Resources/AppIcon.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(size: 1024).write(to: URL(fileURLWithPath: "docs/icon.png"))
print("wrote Resources/AppIcon.iconset and docs/icon.png")
