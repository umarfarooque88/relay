import AppKit
import SwiftUI

/// Draws the app's icon (shown in Finder, System Settings and anywhere else the app is
/// listed; the app itself has no Dock tile). `Relay --render-icon <png>` is run by build.sh
/// to produce the .icns.
///
/// The icon is the product's own signature: the pressure trace ending in the bright "now"
/// dot, on dark glass lit from where the trace arrives.
enum AppIcon {
    static func write(to path: String) -> Bool {
        let side = 1024
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return false }
        draw(in: context.cgContext, side: CGFloat(side))
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// All measurements are on the 1024-point macOS icon grid: an 824-point body, centred,
    /// with continuous corners. The origin is at the bottom-left.
    private static func draw(in context: CGContext, side: CGFloat) {
        context.scaleBy(x: side / 1024, y: side / 1024)
        let space = CGColorSpaceCreateDeviceRGB()
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: body).cgPath

        func gradient(_ stops: [(CGFloat, NSColor)]) -> CGGradient? {
            CGGradient(
                colorsSpace: space, colors: stops.map(\.1.cgColor) as CFArray, locations: stops.map(\.0))
        }
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        }
        let green = rgb(0.19, 0.82, 0.35)
        let mint = rgb(0.56, 0.98, 0.68)
        let now = CGPoint(x: 748, y: 646)

        // The trace: a slow swell, a dip, then the climb to the present. It enters from
        // beyond the left edge, so it reads as a reading already in progress.
        let trace = CGMutablePath()
        trace.move(to: CGPoint(x: 40, y: 366))
        trace.addCurve(
            to: CGPoint(x: 316, y: 448), control1: CGPoint(x: 140, y: 366), control2: CGPoint(x: 222, y: 448))
        trace.addCurve(
            to: CGPoint(x: 512, y: 388), control1: CGPoint(x: 404, y: 448), control2: CGPoint(x: 432, y: 388))
        trace.addCurve(to: now, control1: CGPoint(x: 624, y: 388), control2: CGPoint(x: 648, y: 646))

        // Shadow beneath the body, as the system's own icons carry.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: rgb(0, 0, 0, 0.32).cgColor)
        context.addPath(shape)
        context.setFillColor(rgb(0.05, 0.07, 0.06).cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()

        // Dark glass, a touch green, darker towards the bottom.
        if let glass = gradient([(0, rgb(0.15, 0.20, 0.17)), (1, rgb(0.03, 0.045, 0.038))]) {
            context.drawLinearGradient(
                glass, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
        }
        // The dot lights the glass around it.
        if let glow = gradient([(0, green.withAlphaComponent(0.42)), (1, green.withAlphaComponent(0))]) {
            context.drawRadialGradient(
                glow, startCenter: now, startRadius: 0, endCenter: now, endRadius: 470, options: [])
        }

        // Everything the trace has passed over, fading out below it.
        let area = trace.mutableCopy() ?? CGMutablePath()
        area.addLine(to: CGPoint(x: now.x, y: body.minY))
        area.addLine(to: CGPoint(x: 40, y: body.minY))
        area.closeSubpath()
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(area)
        context.clip()
        if let fill = gradient([(0, green.withAlphaComponent(0.46)), (1, green.withAlphaComponent(0.02))]) {
            context.drawLinearGradient(
                fill, start: CGPoint(x: 0, y: now.y), end: CGPoint(x: 0, y: body.minY + 40), options: [])
        }
        // It thins out under the final climb, so the fill has no hard edge below the dot.
        context.setBlendMode(.destinationIn)
        if let fade = gradient([(0, rgb(0, 0, 0, 1)), (1, rgb(0, 0, 0, 0))]) {
            context.drawLinearGradient(
                fade, start: CGPoint(x: 500, y: 0), end: CGPoint(x: now.x, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.endTransparencyLayer()
        context.restoreGState()

        // The trace itself, brightening as it approaches the present.
        context.saveGState()
        context.setShadow(offset: .zero, blur: 30, color: green.withAlphaComponent(0.55).cgColor)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(trace)
        context.setLineWidth(58)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.replacePathWithStrokedPath()
        context.clip()
        if let stroke = gradient([(0, rgb(0.10, 0.62, 0.27)), (0.6, green), (1, mint)]) {
            context.drawLinearGradient(
                stroke, start: CGPoint(x: body.minX, y: 0), end: CGPoint(x: now.x, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.endTransparencyLayer()
        context.restoreGState()

        // Now: a halo, then the dot.
        context.setFillColor(mint.withAlphaComponent(0.26).cgColor)
        context.fillEllipse(in: CGRect(x: now.x - 104, y: now.y - 104, width: 208, height: 208))
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: rgb(0, 0.2, 0.08, 0.45).cgColor)
        let dot = CGRect(x: now.x - 56, y: now.y - 56, width: 112, height: 112)
        context.addEllipse(in: dot)
        context.clip()
        if let surface = gradient([(0, rgb(1, 1, 1)), (1, rgb(0.74, 1, 0.82))]) {
            context.drawLinearGradient(
                surface, start: CGPoint(x: 0, y: dot.maxY), end: CGPoint(x: 0, y: dot.minY), options: [])
        }
        context.restoreGState()

        // Light across the top of the glass.
        if let sheen = gradient([(0, rgb(1, 1, 1, 0.10)), (1, rgb(1, 1, 1, 0))]) {
            context.drawLinearGradient(
                sheen, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY + 40), options: [])
        }
        context.restoreGState()

        // Rim light, brightest along the top edge. Stroked at twice the width and clipped to
        // the shape, which leaves the inner half.
        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.addPath(shape)
        context.setLineWidth(12)
        context.replacePathWithStrokedPath()
        context.clip()
        if let rim = gradient([(0, rgb(1, 1, 1, 0.50)), (0.45, rgb(1, 1, 1, 0.07)), (1, rgb(1, 1, 1, 0.18))]) {
            context.drawLinearGradient(
                rim, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
        }
        context.restoreGState()
    }
}
