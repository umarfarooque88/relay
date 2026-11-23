import AppKit
import SwiftUI

/// The full readout: a Liquid Glass panel that rises from the Dock bar when the bar is
/// clicked, and returns to it when the bar is clicked again.
@MainActor
final class DetailPanelController {
    private static let cornerRadius: CGFloat = 26
    private static let gapAboveDock: CGFloat = 8
    private static let screenMargin: CGFloat = 8
    /// How far below its resting place the panel starts and ends, so it reads as coming
    /// from, and going back to, the bar beneath it.
    private static let travel: CGFloat = 10

    private let panel: NSPanel
    private let size: NSSize
    /// The intended state; the window itself lags behind it while animating.
    private var isOpen = false
    private var restingFrame = NSRect.zero

    init(model: MemoryModel) {
        let content = LivePanelView(model: model)
        // The layout has a fixed width and a height that follows from its rows.
        let fitted = NSHostingController(rootView: content)
            .sizeThatFits(in: NSSize(width: PanelView.width, height: 10_000))
        size = NSSize(width: PanelView.width, height: fitted.height.rounded(.up))

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Just under the Dock itself, above ordinary windows.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        // Present on every desktop, but not over full-screen apps (the Dock is hidden there too).
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []

        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = Self.cornerRadius
        glass.contentView = hosting

        let root = SurfaceView(frame: panel.contentLayoutRect)
        root.isDraggable = true
        root.menuProvider = { [weak self] in self?.makeMenu() }
        root.onDoubleClick = { ActivityMonitor.open() }
        glass.frame = root.bounds
        glass.autoresizingMask = [.width, .height]
        root.addSubview(glass)
        panel.contentView = root
    }

    /// `anchor` is the bar's frame on screen, when it is known.
    func toggle(above anchor: NSRect?) {
        if isOpen {
            hide()
        } else {
            show(above: anchor)
        }
    }

    /// Opens just above the Dock, centred on the bar. Without a known bar position it is
    /// centred on the pointer when the pointer is on the Dock, otherwise on the screen.
    func show(above anchor: NSRect?) {
        let pointer = NSEvent.mouseLocation
        let reference = anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? pointer
        let screen =
            NSScreen.screens.first { $0.frame.contains(reference) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let pointerIsOnDock = pointer.y <= screen.visibleFrame.minY
        let centre = anchor?.midX ?? (pointerIsOnDock ? pointer.x : screen.frame.midX)
        let minX = screen.frame.minX + Self.screenMargin
        let maxX = screen.frame.maxX - Self.screenMargin - size.width
        // Clear of the Dock, and of the bar itself when the bar is waiting outside the Dock.
        let floor = max(screen.visibleFrame.minY, anchor?.maxY ?? 0)
        restingFrame = NSRect(
            origin: NSPoint(
                x: min(max(centre - size.width / 2, minX), maxX).rounded(),
                y: floor + Self.gapAboveDock),
            size: size)

        isOpen = true
        if !panel.isVisible {
            // Start from where a closing panel would have ended; a panel caught mid-close
            // simply turns round from wherever it is.
            panel.alphaValue = 0
            panel.setFrame(restingFrame.offsetBy(dx: 0, dy: Self.reducedMotion ? 0 : -Self.travel), display: true)
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(restingFrame, display: true)
        }
    }

    @objc func hide() {
        guard isOpen else { return }
        isOpen = false
        // Leaves along the path it arrived by.
        let exit = panel.frame.offsetBy(dx: 0, dy: Self.reducedMotion ? 0 : -Self.travel)
        let duration = 0.18
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(exit, display: true)
        }
        // Taken off screen on a timer, so that closing never depends on the animation
        // reaching its end; a faded-out window left in place would still swallow clicks.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) { [weak self] in
            // Reopened before the close finished: leave it on screen.
            guard let self, !self.isOpen else { return }
            self.panel.orderOut(nil)
        }
    }

    private static var reducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
        menu.addItem(withTitle: "Hide", action: #selector(hide), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func openActivityMonitor() {
        ActivityMonitor.open()
    }
}

enum ActivityMonitor {
    @MainActor static func open() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// The glass surfaces only display information, so the whole surface is one control:
/// click (or drag, where allowed), double-click, and right-click for a menu.
final class SurfaceView: NSView {
    var menuProvider: (() -> NSMenu?)?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    /// Lets the window be dragged freely by its surface.
    var isDraggable = false
    /// For surfaces that manage their own dragging: called with the horizontal distance
    /// the pointer has travelled since the press, then once when the drag ends.
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    /// Called on press and on release, for feedback that starts with the press.
    var onPressChange: ((Bool) -> Void)?

    private var pressX: CGFloat?
    private var isDragging = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let onDoubleClick {
            onDoubleClick()
        } else if isDraggable {
            window?.performDrag(with: event)
        } else {
            // Screen coordinates, because the window moves under the pointer during a drag.
            pressX = NSEvent.mouseLocation.x
            onPressChange?(true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let onDrag, let pressX else { return }
        let distance = NSEvent.mouseLocation.x - pressX
        // A few points of slack, so a slightly unsteady click is still a click.
        if isDragging || abs(distance) > 4 {
            isDragging = true
            onDrag(distance)
        }
    }

    override func mouseUp(with event: NSEvent) {
        pressX = nil
        onPressChange?(false)
        if isDragging {
            isDragging = false
            onDragEnd?()
        } else if event.clickCount == 1, bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }
}
