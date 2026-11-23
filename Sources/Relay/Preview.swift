import AppKit
import MemoryKit
import SwiftUI

/// Renders the bar and the readout to an image without putting anything on screen
/// (`Relay --render-preview <png>`). The glass behind them is not part of the picture;
/// a flat dark backdrop stands in for it.
@MainActor
enum Preview {
    static func write(to path: String) -> Bool {
        guard var snapshot = MemorySampler().sample() else { return false }
        let pressures = CommandLine.arguments.contains("--high") ? (0.80, 1.0) : (0.38, 0.46)
        var history = PressureHistory(capacity: MemoryModel.historyLength)
        for index in 0..<MemoryModel.historyLength {
            let t = Double(index)
            let wave = 0.5 + 0.35 * sin(t / 17) + 0.15 * sin(t / 4.3)
            history.append(.init(value: pressures.0 + (pressures.1 - pressures.0) * wave, level: .normal))
        }
        snapshot.pressure = history.points.last?.value ?? snapshot.pressure
        // The widest values the legend has to fit.
        if CommandLine.arguments.contains("--high") { snapshot.wired = 24_620_000_000 }

        // `--light` shows both in light appearance.
        let isLight = CommandLine.arguments.contains("--light")
        let scale: CGFloat = 2
        let barSize = NSSize(width: 196, height: 54)
        let panelContent = PanelView(snapshot: snapshot, history: history)
            .background(Color(white: isLight ? 0.93 : 0.2), in: .rect(cornerRadius: 26))
            .environment(\.colorScheme, isLight ? .light : .dark)
        let renderer = ImageRenderer(content: panelContent)
        renderer.scale = scale
        guard let panelImage = renderer.cgImage else { return false }
        let panelSize = NSSize(width: CGFloat(panelImage.width) / scale, height: CGFloat(panelImage.height) / scale)

        let margin: CGFloat = 20
        let canvas = NSSize(
            width: max(panelSize.width, barSize.width) + 2 * margin,
            height: panelSize.height + barSize.height + 3 * margin)
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return false }
        bitmap.size = canvas
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return false }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(white: isLight ? 0.78 : 0.1, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvas).fill()
        context.cgContext.draw(
            panelImage,
            in: CGRect(x: margin, y: barSize.height + 2 * margin, width: panelSize.width, height: panelSize.height))

        // The bar draws straight into the picture, as it would into its own layer.
        let bar = BarContentView(frame: NSRect(origin: .zero, size: barSize))
        bar.snapshot = snapshot
        bar.history = history
        bar.isOnDock = true
        context.cgContext.translateBy(x: (canvas.width - barSize.width) / 2, y: margin)
        NSAppearance(named: isLight ? .aqua : .darkAqua)?.performAsCurrentDrawingAppearance {
            bar.draw(bar.bounds)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
