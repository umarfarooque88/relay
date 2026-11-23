import AppKit
import ServiceManagement

/// The two things Relay needs before it can sit in the Dock, asked for in plain words the
/// first time (and any later time one of them is missing). Declining either leaves Relay
/// running in the corner of the screen, with the same steps in its right-click menu.
@MainActor
enum Setup {
    static func runIfNeeded() {
        if !DockSlot.isInstalled { offerSlot() }
        if !DockLocator.isTrusted { offerAccess() }
    }

    private static func offerSlot() {
        let alert = NSAlert()
        alert.messageText = "Give Relay a place in the Dock"
        alert.informativeText = """
            Relay sits inside the Dock, on three blank spaces at its right-hand end. \
            Adding them restarts the Dock once, which takes a couple of seconds. \
            You can take Relay out again at any time from its right-click menu.
            """
        alert.addButton(withTitle: "Add to Dock")
        alert.addButton(withTitle: "Not Now")
        if present(alert) == .alertFirstButtonReturn {
            DockSlot.install()
        }
    }

    private static func offerAccess() {
        let alert = NSAlert()
        alert.messageText = "Let Relay find its place"
        alert.informativeText = """
            macOS only tells an app where things are in the Dock if the app has Accessibility \
            access. Relay uses it for that and nothing else. In System Settings, under \
            Privacy & Security › Accessibility, turn on Relay.
            """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if present(alert) == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    static func openAccessibilitySettings() {
        // Registers Relay in the list, so there is a switch to turn on.
        DockLocator.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Asks before taking Relay out of the Dock. Returns whether the user agreed.
    static func confirmRemoval() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Remove Relay from the Dock?"
        alert.informativeText = """
            The three spaces Relay uses are taken out of the Dock, which restarts it once, \
            and Relay quits. It will no longer open at login.
            """
        alert.addButton(withTitle: "Remove and Quit")
        alert.addButton(withTitle: "Cancel")
        return present(alert) == .alertFirstButtonReturn
    }

    /// Relay is never the active app, so an alert has to be brought forward explicitly.
    private static func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}

/// Whether macOS opens Relay when the user logs in.
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns whether the change was accepted.
    @discardableResult
    static func set(_ isOn: Bool) -> Bool {
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
