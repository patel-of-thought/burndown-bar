import AppKit

/// Monochrome template version of the app icon: a 75% progress ring around an AI sparkle.
enum MenuBarIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let lineWidth = size * 0.1
            let radius = size / 2 - lineWidth / 2 - size * 0.03

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(0.35).setStroke()
            track.stroke()

            // Clockwise from 12 o'clock, 270 degrees.
            let progress = NSBezierPath()
            progress.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 180, clockwise: true)
            progress.lineWidth = lineWidth
            progress.lineCapStyle = .round
            NSColor.black.setStroke()
            progress.stroke()

            let reach = size * 0.27
            let pinch = reach * 0.18
            let sparkle = NSBezierPath()
            sparkle.move(to: NSPoint(x: center.x, y: center.y + reach))
            sparkle.curve(to: NSPoint(x: center.x + reach, y: center.y),
                          controlPoint1: NSPoint(x: center.x + pinch, y: center.y + pinch),
                          controlPoint2: NSPoint(x: center.x + pinch, y: center.y + pinch))
            sparkle.curve(to: NSPoint(x: center.x, y: center.y - reach),
                          controlPoint1: NSPoint(x: center.x + pinch, y: center.y - pinch),
                          controlPoint2: NSPoint(x: center.x + pinch, y: center.y - pinch))
            sparkle.curve(to: NSPoint(x: center.x - reach, y: center.y),
                          controlPoint1: NSPoint(x: center.x - pinch, y: center.y - pinch),
                          controlPoint2: NSPoint(x: center.x - pinch, y: center.y - pinch))
            sparkle.curve(to: NSPoint(x: center.x, y: center.y + reach),
                          controlPoint1: NSPoint(x: center.x - pinch, y: center.y + pinch),
                          controlPoint2: NSPoint(x: center.x - pinch, y: center.y + pinch))
            sparkle.close()
            NSColor.black.setFill()
            sparkle.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "BurndownBar"
        return image
    }
}
