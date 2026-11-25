// Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
import AppKit

/// kaju's look: a ginger palette (after the cat) on a warm dark background,
/// and a small cat-ear glyph as the mark.
enum Theme {
    static let ginger = NSColor(srgbRed: 0.929, green: 0.549, blue: 0.220, alpha: 1)   // #ED8C38
    static let cream = NSColor(srgbRed: 0.980, green: 0.800, blue: 0.580, alpha: 1)    // #FACC94
    static let background = NSColor(srgbRed: 0.110, green: 0.098, blue: 0.090, alpha: 0.97)
    static let card = NSColor(srgbRed: 0.172, green: 0.153, blue: 0.137, alpha: 1)
    static let field = NSColor(srgbRed: 0.125, green: 0.114, blue: 0.106, alpha: 1)
    static let dim = NSColor(white: 0.55, alpha: 1)
    static let faint = NSColor(white: 0.45, alpha: 1)
    static let text = NSColor(white: 0.93, alpha: 1)

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Two cat ears, drawn as rounded triangles.
    static func drawEars(in rect: NSRect, color: NSColor) {
        color.setFill()
        let w = rect.width, h = rect.height
        for left in [true, false] {
            let x0 = rect.minX + (left ? 0 : w * 0.54)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x0, y: rect.minY))
            path.line(to: NSPoint(x: x0 + w * 0.46, y: rect.minY))
            path.line(to: NSPoint(x: x0 + (left ? w * 0.14 : w * 0.32), y: rect.minY + h))
            path.close()
            path.lineJoinStyle = .round
            path.fill()
        }
    }

    /// The glyph as an image, e.g. for the menu bar (template) or a header.
    static func earsImage(size: NSSize, color: NSColor = .black, template: Bool = false) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            drawEars(in: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.18), color: color)
            return true
        }
        img.isTemplate = template
        return img
    }
}

/// The cat-ear glyph as a view.
final class EarsView: NSView {
    var color: NSColor = Theme.ginger { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        Theme.drawEars(in: bounds.insetBy(dx: 1, dy: bounds.height * 0.2), color: color)
    }
    // Let clicks fall through, so the view can sit on a draggable background.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
