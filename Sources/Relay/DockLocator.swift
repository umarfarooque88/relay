import AppKit
import ApplicationServices

/// The bar's place in the Dock is three blank spacer tiles in a row. Spacers are the only
/// Dock items with no running-app dot and no hover name, so they hold the space while the
/// glass bar window is laid over them.
enum DockSlot {
    static let spacerCount = 3

    private static var domain: CFString { "com.apple.dock" as CFString }
    private static let sections = ["persistent-apps", "persistent-others"]

    /// Whether the Dock's settings contain the slot: three spacers next to each other.
    static var isInstalled: Bool {
        CFPreferencesAppSynchronize(domain)
        return sections.contains { runOfSpacers(in: entries(of: $0)) != nil }
    }

    private static func entries(of section: String) -> [Any] {
        CFPreferencesCopyAppValue(section as CFString, domain) as? [Any] ?? []
    }

    /// Where the first three adjacent spacers start, if there are any.
    private static func runOfSpacers(in entries: [Any]) -> Int? {
        var run = 0
        for (index, entry) in entries.enumerated() {
            let isSpacer = (entry as? [String: Any])?["tile-type"] as? String == "spacer-tile"
            run = isSpacer ? run + 1 : 0
            if run == spacerCount { return index - run + 1 }
        }
        return nil
    }

    /// Takes the slot's three spacers back out of the Dock and restarts the Dock.
    /// Returns false, changing nothing, if there is no slot.
    @discardableResult
    static func remove() -> Bool {
        CFPreferencesAppSynchronize(domain)
        for section in sections {
            var entries = entries(of: section)
            guard let start = runOfSpacers(in: entries) else { continue }
            entries.removeSubrange(start..<start + spacerCount)
            CFPreferencesSetAppValue(section as CFString, entries as CFArray, domain)
            guard CFPreferencesAppSynchronize(domain) else { return false }
            restartDock()
            return true
        }
        return false
    }

    /// Adds three spacers at the right-hand end of the Dock (before the Trash) and restarts
    /// the Dock so it picks them up. They can be dragged elsewhere, or out, like any Dock item.
    static func install() {
        for _ in 0..<spacerCount {
            run(
                "/usr/bin/defaults",
                ["write", "com.apple.dock", "persistent-others", "-array-add",
                    #"{"tile-data"={}; "tile-type"="spacer-tile";}"#])
        }
        restartDock()
    }

    static func restartDock() {
        run("/usr/bin/killall", ["Dock"])
    }

    private static func run(_ tool: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }
}

/// Finds where the Dock has put the slot, using the Accessibility API. This is the only way
/// to learn a Dock item's position, and it needs the user to allow Relay under
/// System Settings › Privacy & Security › Accessibility.
@MainActor
final class DockLocator {
    enum Slot {
        /// The three spacers' frames, left to right, in Cocoa screen coordinates.
        case found([NSRect])
        /// No run of three spacers in the Dock, or the Dock cannot be read.
        case missing
    }

    private var spacers: [AXUIElement] = []
    private var lastSearch = Date.distantPast

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to the Accessibility settings.
    static func requestTrust() {
        // The key is the value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func locate() -> Slot {
        if spacers.count != DockSlot.spacerCount {
            // Walking the whole Dock costs ~25 ms, so do it at most once a second.
            guard Date().timeIntervalSince(lastSearch) >= 1 else { return .missing }
            lastSearch = Date()
            spacers = findSpacers()
            guard spacers.count == DockSlot.spacerCount else { return .missing }
        }
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return .missing }

        var frames: [NSRect] = []
        for spacer in spacers {
            guard let frame = Self.frame(of: spacer) else {
                spacers = []  // The Dock rebuilt its items; look them up again next time.
                return .missing
            }
            // Accessibility measures from the top-left of the primary display.
            frames.append(
                NSRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height))
        }
        // If the user dragged one of them away they are no longer a slot; search afresh.
        for (left, right) in zip(frames, frames.dropFirst()) where abs(right.minX - left.maxX) > 1.5 {
            spacers = []
            return .missing
        }
        return .found(frames)
    }

    /// The first three spacers that sit next to each other in the Dock.
    private func findSpacers() -> [AXUIElement] {
        let items = Self.dockItems()
        guard let start = Self.slotStart(in: items) else { return [] }
        return items[start..<start + DockSlot.spacerCount].map(\.element)
    }

    // MARK: Moving the slot

    /// Moves the slot to the gap between Dock items nearest to `x` (a screen x position),
    /// by reordering the Dock's settings and restarting the Dock, which is the only way to
    /// make it re-read them. Returns false, changing nothing, if the slot is already there
    /// or the Dock's layout cannot be matched to its settings with certainty.
    ///
    /// The Dock only keeps user-arranged items in two places: among the pinned apps (after
    /// Finder) and among the folders (before the Trash). Finder is always first and the
    /// Trash always last, so those are the limits.
    func moveSlot(nearX x: CGFloat) -> Bool {
        let items = Self.dockItems()
        let count = DockSlot.spacerCount
        let separators = items.indices.filter { items[$0].subrole == "AXSeparatorDockItem" }
        guard
            let slotStart = Self.slotStart(in: items),
            let firstSeparator = separators.first, let lastSeparator = separators.last,
            let trash = items.lastIndex(where: { $0.subrole == "AXTrashDockItem" }),
            firstSeparator >= 1, trash > lastSeparator
        else { return false }
        let slot = slotStart..<slotStart + count

        // Each section, matched one-to-one against its array in the Dock's settings.
        // A section whose counts disagree is left alone rather than guessed at.
        struct Section {
            let key: String
            var settings: [Any]
            /// Indices into `items`, in order, of the entries that `settings` describes.
            let members: [Int]
        }
        CFPreferencesAppSynchronize(Self.dockDomain)
        let ranges = [("persistent-apps", 1..<firstSeparator), ("persistent-others", (lastSeparator + 1)..<trash)]
        var sections: [Section] = ranges.compactMap { key, range in
            // Minimised windows sit in the Dock but are not part of its settings.
            let members = range.filter { items[$0].subrole != "AXMinimizedWindowDockItem" }
            guard
                let settings = CFPreferencesCopyAppValue(key as CFString, Self.dockDomain) as? [Any],
                settings.count == members.count
            else { return nil }
            return Section(key: key, settings: settings, members: members)
        }

        guard
            let source = sections.firstIndex(where: { $0.members.contains(slot.lowerBound) }),
            let sourceOffset = sections[source].members.firstIndex(of: slot.lowerBound),
            sourceOffset + count <= sections[source].members.count,
            Array(sections[source].members[sourceOffset..<sourceOffset + count]) == Array(slot),
            sections[source].settings[sourceOffset..<sourceOffset + count].allSatisfy({
                ($0 as? [String: Any])?["tile-type"] as? String == "spacer-tile"
            })
        else { return false }

        // Every gap the slot could occupy, by where that gap is on screen right now.
        var best: (section: Int, offset: Int, distance: CGFloat)?
        for (index, section) in sections.enumerated() {
            let others = section.members.filter { !slot.contains($0) }
            for offset in 0...others.count {
                let isCurrent = index == source && offset == sourceOffset
                let gapX: CGFloat
                if isCurrent {
                    gapX = (items[slot.lowerBound].frame.minX + items[slot.upperBound - 1].frame.maxX) / 2
                } else if offset < others.count {
                    gapX = items[others[offset]].frame.minX
                } else if let last = others.last {
                    gapX = items[last].frame.maxX
                } else {
                    gapX = items[index == 0 ? firstSeparator : trash].frame.minX
                }
                let distance = abs(gapX - x)
                if best == nil || distance < best!.distance { best = (index, offset, distance) }
            }
        }
        guard let best, !(best.section == source && best.offset == sourceOffset) else { return false }

        let spacers = Array(sections[source].settings[sourceOffset..<sourceOffset + count])
        sections[source].settings.removeSubrange(sourceOffset..<sourceOffset + count)
        sections[best.section].settings.insert(contentsOf: spacers, at: best.offset)
        for section in sections where section.key == sections[source].key || section.key == sections[best.section].key {
            CFPreferencesSetAppValue(section.key as CFString, section.settings as CFArray, Self.dockDomain)
        }
        guard CFPreferencesAppSynchronize(Self.dockDomain) else { return false }

        self.spacers = []
        lastSearch = .distantPast
        DockSlot.restartDock()
        return true
    }

    private static let dockDomain = "com.apple.dock" as CFString

    private struct Item {
        let element: AXUIElement
        let subrole: String
        let frame: CGRect
    }

    /// Everything in the Dock, left to right.
    private static func dockItems() -> [Item] {
        guard
            let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [] }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = children(of: dockElement).first else { return [] }
        return children(of: list).compactMap { element in
            guard let subrole: String = attribute(kAXSubroleAttribute, of: element),
                let frame = frame(of: element)
            else { return nil }
            return Item(element: element, subrole: subrole, frame: frame)
        }
    }

    /// Index of the first run of three spacers in a row.
    private static func slotStart(in items: [Item]) -> Int? {
        var run = 0
        for (index, item) in items.enumerated() {
            run = item.subrole == "AXSpacerDockItem" ? run + 1 : 0
            if run == DockSlot.spacerCount { return index - run + 1 }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) ?? []
    }

    private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
            let position, let size,
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard
            AXValueGetValue(position as! AXValue, .cgPoint, &origin),
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
