import AppKit
import MemoryKit
import SwiftUI

/// The running pressure graph, drawn the same way in the Dock bar and in the readout:
/// a smooth line with a fill that melts away beneath it, fading in from the oldest readings
/// and ending in a dot at the present. The full height of `rect` is 100% pressure, the
/// same absolute scale as Activity Monitor, and nothing is drawn outside `rect`.
enum Sparkline {
    /// Expects a context with its origin at the bottom-left. `unit` scales the stroke and dot.
    static func draw(_ history: PressureHistory, in context: CGContext, rect: CGRect, unit: CGFloat) {
        let points = history.points
        guard let newest = points.last else { return }
        let dotRadius = 2.25 * unit
        let haloRadius = 3.5 * unit
        // The newest reading sits just inside the right edge, and 100% just inside the top,
        // leaving room for the dot.
        let plot = CGRect(
            x: rect.minX, y: rect.minY, width: rect.width - haloRadius, height: rect.height - haloRadius)
        let step = plot.width / CGFloat(history.capacity - 1)
        let firstX = plot.maxX - step * CGFloat(points.count - 1)
        let space = CGColorSpaceCreateDeviceRGB()

        func position(_ index: Int) -> CGPoint {
            CGPoint(x: firstX + step * CGFloat(index), y: plot.minY + plot.height * points[index].value)
        }

        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        // Each stretch takes the colour of the pressure level it was recorded at.
        var start = 0
        while start < points.count - 1 {
            let level = points[start + 1].level
            var end = start + 1
            while end < points.count - 1, points[end + 1].level == level { end += 1 }

            // Curves through the midpoints round off the one-percent steps in the data.
            let line = CGMutablePath()
            line.move(to: position(start))
            for index in (start + 1)..<end {
                let here = position(index)
                let next = position(index + 1)
                line.addQuadCurve(to: CGPoint(x: (here.x + next.x) / 2, y: (here.y + next.y) / 2), control: here)
            }
            line.addLine(to: position(end))

            let area = line.mutableCopy() ?? CGMutablePath()
            area.addLine(to: CGPoint(x: position(end).x, y: rect.minY))
            area.addLine(to: CGPoint(x: position(start).x, y: rect.minY))
            area.closeSubpath()

            let color = level.nsColor
            context.saveGState()
            context.addPath(area)
            context.clip()
            if let fill = CGGradient(
                colorsSpace: space,
                colors: [color.withAlphaComponent(0.42).cgColor, color.withAlphaComponent(0.03).cgColor] as CFArray,
                locations: [0, 1])
            {
                context.drawLinearGradient(
                    fill, start: CGPoint(x: 0, y: plot.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
            }
            context.restoreGState()

            context.addPath(line)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(1.5 * unit)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
            start = end
        }

        // Older readings dissolve at the left edge instead of ending in a hard cut.
        context.setBlendMode(.destinationIn)
        if let fade = CGGradient(
            colorSpace: space, colorComponents: [0, 0, 0, 0, 0, 0, 0, 1], locations: [0, 1], count: 2)
        {
            context.drawLinearGradient(
                fade, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.minX + rect.width * 0.22, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.endTransparencyLayer()
        context.restoreGState()

        // Now.
        let now = position(points.count - 1)
        let color = newest.level.nsColor
        context.setFillColor(color.withAlphaComponent(0.28).cgColor)
        context.fillEllipse(
            in: CGRect(x: now.x - haloRadius, y: now.y - haloRadius, width: 2 * haloRadius, height: 2 * haloRadius))
        context.setFillColor(color.cgColor)
        context.fillEllipse(
            in: CGRect(x: now.x - dotRadius, y: now.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius))
    }
}

/// The sparkline as a SwiftUI view, for the readout.
struct SparklineView: View {
    let history: PressureHistory

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cgContext in
                // Canvas measures from the top-left; the drawing measures from the bottom-left.
                cgContext.translateBy(x: 0, y: size.height)
                cgContext.scaleBy(x: 1, y: -1)
                Sparkline.draw(history, in: cgContext, rect: CGRect(origin: .zero, size: size), unit: 1.2)
            }
        }
        .accessibilityHidden(true)
    }
}

extension PressureLevel {
    var nsColor: NSColor {
        switch self {
        case .normal: .systemGreen
        case .warning: .systemYellow
        case .critical: .systemRed
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    var name: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}
