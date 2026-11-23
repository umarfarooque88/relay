import AppKit
import MemoryKit
import SwiftUI

/// The single wide bar. Dock tiles are square and cannot host system glass, so the bar is
/// a borderless window one level above the Dock, laid exactly over a slot of three blank
/// spacers. It draws one real Liquid Glass surface across the whole slot.
@MainActor
final class BarOverlayController {
    /// How the Dock lays out a tile inside its item frame (measured at tile sizes 59 and 73):
    /// the item is 4 pt wider and 20 pt taller than the tile, with the tile 5 pt above the
    /// item's bottom edge and centred horizontally.
    private static let tileSidePadding: CGFloat = 2
    private static let tileBottomOffset: CGFloat = 5
    /// The macOS icon grid: artwork is 103/128 of the tile.
    private static let iconInset: CGFloat = 12.5 / 128
    /// Size and margin used when there is no slot to sit in.
    private static let looseSize = NSSize(width: 176, height: 48)
    private static let looseMargin: CGFloat = 16

    private let panel: NSPanel
    private let glass = NSGlassEffectView()
    private let content = BarContentView()
    private let model: MemoryModel

    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    /// Called when the bar is dropped after a drag, with the x position of its centre.
    var onDrop: ((CGFloat) -> Void)?

    /// The bar's frame while it is on screen.
    private(set) var frame: NSRect?
    private var dragStart: NSRect?
    /// Where the bar was last told to rest; a drag clears it so the bar is re-settled after.
    private var settledFrame: NSRect?
    private var missingSince: Date?

    init(model: MemoryModel) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.looseSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // One level above the Dock, so the bar sits on the Dock's glass rather than under it.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        // On every desktop; not in full-screen spaces, where the Dock is hidden.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // System glass is only used away from the Dock. In the Dock the bar sits directly on
        // the Dock's own Liquid Glass: a second glass layer stacked on it (regular or clear,
        // AppKit or SwiftUI - all were tried) renders as a flat grey slab.
        glass.style = .regular

        let root = SurfaceView(frame: panel.contentLayoutRect)
        root.onClick = { [weak self] in self?.onClick?() }
        root.menuProvider = { [weak self] in self?.menuProvider?() }
        // Feedback on press, not on release.
        root.onPressChange = { [weak self] isPressed in
            self?.content.animator().alphaValue = isPressed ? 0.6 : 1
        }
        root.onDrag = { [weak self] distance in self?.drag(by: distance) }
        root.onDragEnd = { [weak self] in self?.endDrag() }
        for layer in [glass, content] {
            layer.frame = root.bounds
            layer.autoresizingMask = [.width, .height]
            root.addSubview(layer)
        }
        panel.contentView = root

        refresh()
        model.onChange = { [weak self] in self?.refresh() }
    }

    /// Hands the newest reading to the content view, which redraws itself.
    private func refresh() {
        content.snapshot = model.snapshot
        content.history = model.history
        content.needsDisplay = true
    }

    /// Puts the bar in its Dock slot. With no slot (no spacers yet, or no Accessibility
    /// access) it waits in the bottom-right corner so it is still visible and its menu
    /// can finish the setup. While the Dock itself is off screen the bar hides with it.
    func place(in slot: DockLocator.Slot) {
        guard dragStart == nil else { return }  // The pointer has it.
        let target: NSRect?
        switch slot {
        case .found(let frames):
            missingSince = nil
            target = Self.slotFrame(covering: frames)
            setOnDock(true)
        case .missing:
            // Short gaps are normal while the Dock restarts or rebuilds its items;
            // stay put through them instead of jumping to the corner and back.
            let now = Date()
            let since = missingSince ?? now
            missingSince = since
            if frame != nil, now.timeIntervalSince(since) < 6 { return }
            target = Self.looseFrame()
            setOnDock(false)
        }
        guard let target else {
            if panel.isVisible { panel.orderOut(nil) }
            frame = nil
            settledFrame = nil
            return
        }
        if target != settledFrame {
            glass.cornerRadius = target.height * BarContentView.cornerRadiusRatio
            if panel.isVisible, panel.frame.size == target.size {
                // Glide to follow the Dock (or to settle after a drag) rather than jump.
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(target, display: true)
                }
            } else {
                panel.setFrame(target, display: true)
            }
            settledFrame = target
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
        frame = target
    }

    private func setOnDock(_ isOnDock: Bool) {
        guard content.isOnDock != isOnDock || glass.isHidden != isOnDock else { return }
        glass.isHidden = isOnDock
        content.isOnDock = isOnDock
        content.needsDisplay = true
    }

    // MARK: Dragging

    /// The bar slides along the Dock with the pointer.
    private func drag(by distance: CGFloat) {
        let start = dragStart ?? panel.frame
        dragStart = start
        guard let screen = panel.screen ?? NSScreen.screens.first else { return }
        var moved = start
        moved.origin.x = min(max(start.minX + distance, screen.frame.minX), screen.frame.maxX - start.width)
        panel.setFrameOrigin(moved.origin)
        frame = moved
        settledFrame = nil
    }

    /// On release the slot is moved to the nearest gap in the Dock; `place` then settles
    /// the bar into it (or back where it was, if nothing moved).
    private func endDrag() {
        dragStart = nil
        onDrop?(panel.frame.midX)
    }

    /// The bar across the spacers, the same height as the icons beside it and on the same
    /// line, so it reads as one wide icon. Nil while the Dock is off screen (hidden).
    private static func slotFrame(covering spacers: [NSRect]) -> NSRect? {
        guard let first = spacers.first, let last = spacers.last else { return nil }
        let tile = first.width - 2 * tileSidePadding
        let inset = tile * iconInset
        let bar = NSRect(
            x: first.minX + tileSidePadding + inset,
            y: first.minY + tileBottomOffset + inset,
            width: last.maxX - first.minX - 2 * (tileSidePadding + inset),
            height: tile - 2 * inset)
        guard bar.height >= 24, NSScreen.screens.contains(where: { $0.frame.contains(bar) }) else { return nil }
        return bar
    }

    private static func looseFrame() -> NSRect? {
        guard let screen = NSScreen.screens.first else { return nil }
        return NSRect(
            x: screen.frame.maxX - looseMargin - looseSize.width,
            y: screen.frame.minY + looseMargin,
            width: looseSize.width, height: looseSize.height)
    }
}

/// Bar content, in the manner of a system widget: a quiet caption, the reading as the one
/// prominent figure, and the running graph as a soft sparkline beneath them.
///
/// Drawn with Core Graphics rather than SwiftUI: this view repaints twice a second for as
/// long as the Mac is on, and the SwiftUI version spent about 5% of a core doing it.
final class BarContentView: NSView {
    /// The macOS icon grid's corner radius (23.5 on a 103-unit body), so the bar's corners
    /// match the icons beside it.
    static let cornerRadiusRatio: CGFloat = 23.5 / 103

    var snapshot: MemorySnapshot?
    var history = PressureHistory(capacity: 2)
    /// True while the bar sits in its Dock slot, on the Dock's own glass.
    var isOnDock = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Designed at 48 pt tall (a 59 pt Dock tile); everything scales with the Dock.
        let unit = bounds.height / 48
        if isOnDock { drawEdgeLight(in: context) }

        // The reading sits high in the bar and the graph is confined to the space beneath it,
        // so the two cannot meet even at 100% pressure.
        let figureFont = Self.rounded(ofSize: 16 * unit)
        let baseline = bounds.maxY - 6.5 * unit - figureFont.capHeight
        let sides = 11 * unit
        drawReading(left: bounds.minX + sides, right: bounds.maxX - sides, baseline: baseline, unit: unit)

        let bottom = bounds.minY + 5.5 * unit
        let graph = NSRect(
            x: bounds.minX + sides, y: bottom,
            width: bounds.width - 2 * sides, height: baseline - 3.5 * unit - bottom)
        Sparkline.draw(history, in: context, rect: graph, unit: unit)
    }

    /// On the Dock the bar has no fill of its own: the Dock's glass is the surface. Only the
    /// light an edge of glass would catch is drawn - a faint sheen and a bright rim.
    private func drawEdgeLight(in context: CGContext) {
        let shape = RoundedRectangle(cornerRadius: bounds.height * Self.cornerRadiusRatio, style: .continuous)
            .path(in: bounds).cgPath
        let space = CGColorSpaceCreateDeviceRGB()
        let top = CGPoint(x: 0, y: bounds.maxY)
        let bottom = CGPoint(x: 0, y: bounds.minY)

        context.saveGState()
        context.addPath(shape)
        context.clip()
        if let sheen = CGGradient(
            colorSpace: space, colorComponents: [1, 1, 1, 0.09, 1, 1, 1, 0.02], locations: [0, 1], count: 2)
        {
            context.drawLinearGradient(sheen, start: top, end: bottom, options: [])
        }
        // Stroked at 2 pt and clipped to the shape, which leaves a 1 pt rim on the inside.
        context.addPath(shape)
        context.setLineWidth(2)
        context.replacePathWithStrokedPath()
        context.clip()
        if let rim = CGGradient(
            colorSpace: space, colorComponents: [1, 1, 1, 0.50, 1, 1, 1, 0.08, 1, 1, 1, 0.20],
            locations: [0, 0.5, 1], count: 3)
        {
            context.drawLinearGradient(rim, start: top, end: bottom, options: [])
        }
        context.restoreGState()
    }

    /// "Memory Pressure" on the left, the percentage on the right, on one baseline.
    private func drawReading(left: CGFloat, right: CGFloat, baseline: CGFloat, unit: CGFloat) {
        let captionFont = NSFont.systemFont(ofSize: 10.5 * unit, weight: .medium)
        let figureFont = Self.rounded(ofSize: 16 * unit)
        let signFont = Self.rounded(ofSize: 10.5 * unit)

        let figure = NSAttributedString(
            string: snapshot.map { "\(Int(($0.pressure * 100).rounded()))" } ?? "–",
            attributes: [.font: figureFont, .foregroundColor: NSColor.labelColor, .kern: -0.2 * unit])
        let sign = NSAttributedString(
            string: "%", attributes: [.font: signFont, .foregroundColor: NSColor.secondaryLabelColor])
        let caption = NSAttributedString(
            string: "Memory Pressure",
            attributes: [.font: captionFont, .foregroundColor: NSColor.secondaryLabelColor])

        // Text is positioned by the bottom of its line box, which lies a descender below the baseline.
        let signX = right - sign.size().width
        sign.draw(at: NSPoint(x: signX, y: baseline + signFont.descender))
        figure.draw(at: NSPoint(x: signX - 0.5 * unit - figure.size().width, y: baseline + figureFont.descender))
        caption.draw(at: NSPoint(x: left, y: baseline + captionFont.descender))
    }

    private static func rounded(ofSize size: CGFloat) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { "Memory pressure" }
    override func accessibilityValue() -> Any? {
        snapshot.map { "\(Int(($0.pressure * 100).rounded())) percent" } ?? "unavailable"
    }
}
