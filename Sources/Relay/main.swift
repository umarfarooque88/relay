import AppKit

/// Relay has no Dock tile of its own. It keeps one Liquid Glass bar laid over a slot
/// of three blank spacers in the Dock; clicking the bar opens the full readout above it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MemoryModel()
    private let locator = DockLocator()
    private var detailPanel: DetailPanelController?
    private var bar: BarOverlayController?
    private var trackingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        detailPanel = DetailPanelController(model: model)

        let bar = BarOverlayController(model: model)
        bar.onClick = { [weak self] in self?.toggleDetails() }
        bar.menuProvider = { [weak self] in self?.makeMenu() }
        bar.onDrop = { [weak self] x in
            // Nothing to rearrange until the slot exists and the Dock can be read.
            guard let self, DockLocator.isTrusted else { return }
            _ = self.locator.moveSlot(nearX: x)
        }
        self.bar = bar

        // The Dock re-centres whenever an app opens or quits; follow it closely.
        placeBar()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeBar() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer

        // After the first pass of the run loop, so the bar is already on screen behind it.
        DispatchQueue.main.async { Setup.runIfNeeded() }
    }

    /// Opening the app again while it is running toggles the full readout.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        toggleDetails()
        return false
    }

    private func placeBar() {
        bar?.place(in: DockLocator.isTrusted ? locator.locate() : .missing)
    }

    // MARK: Actions

    @objc private func toggleDetails() {
        detailPanel?.toggle(above: bar?.frame)
    }

    @objc private func openActivityMonitor() {
        ActivityMonitor.open()
    }

    @objc private func allowAccessibility() {
        Setup.openAccessibilitySettings()
    }

    @objc private func addSlotToDock() {
        DockSlot.install()
    }

    @objc private func toggleOpenAtLogin() {
        LoginItem.set(!LoginItem.isOn)
    }

    @objc private func removeFromDock() {
        guard Setup.confirmRemoval() else { return }
        LoginItem.set(false)
        DockSlot.remove()
        NSApp.terminate(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show or Hide Details", action: #selector(toggleDetails), keyEquivalent: "")
        menu.addItem(withTitle: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")

        // Setup steps appear only while they are still needed.
        let needsAccess = !DockLocator.isTrusted
        let needsSlot = !DockSlot.isInstalled
        if needsAccess || needsSlot {
            menu.addItem(.separator())
            if needsSlot {
                menu.addItem(withTitle: "Add Slot to Dock", action: #selector(addSlotToDock), keyEquivalent: "")
            }
            if needsAccess {
                menu.addItem(
                    withTitle: "Allow Accessibility Access…", action: #selector(allowAccessibility),
                    keyEquivalent: "")
            }
        }

        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
        login.state = LoginItem.isOn ? .on : .off
        if !needsSlot {
            menu.addItem(withTitle: "Remove from Dock and Quit…", action: #selector(removeFromDock), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Quit Relay", action: #selector(quit), keyEquivalent: "")
        for item in menu.items where !item.isSeparatorItem { item.target = self }
        return menu
    }
}

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--render-icon"), arguments.indices.contains(flag + 1) {
    exit(AppIcon.write(to: arguments[flag + 1]) ? 0 : 1)
}

// `--render-preview <png>` draws the bar and the readout with the current readings and a
// sample history into an image, for checking the layout without the screen.
if let flag = arguments.firstIndex(of: "--render-preview"), arguments.indices.contains(flag + 1) {
    exit(Preview.write(to: arguments[flag + 1]) ? 0 : 1)
}

// `--move-slot <x>` does what dropping the bar at screen position x does; for scripting and tests.
if let flag = arguments.firstIndex(of: "--move-slot"), arguments.indices.contains(flag + 1),
    let x = Double(arguments[flag + 1])
{
    exit(DockLocator().moveSlot(nearX: x) ? 0 : 1)
}

// `--open-at-login on|off|status` changes or reports whether Relay opens at login.
if let flag = arguments.firstIndex(of: "--open-at-login"), arguments.indices.contains(flag + 1) {
    switch arguments[flag + 1] {
    case "on": exit(LoginItem.set(true) ? 0 : 1)
    case "off": exit(LoginItem.set(false) ? 0 : 1)
    default:
        print(LoginItem.isOn ? "on" : "off")
        exit(0)
    }
}

// `--remove-slot` takes Relay's three spaces out of the Dock, as the menu item does.
if arguments.contains("--remove-slot") {
    exit(DockSlot.remove() ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
