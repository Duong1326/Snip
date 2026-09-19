import AppKit
import SwiftUI
import CoreGraphics

// MARK: - AppDelegate
// Central coordinator for the app:
//  - Creates NSStatusItem (menu bar icon)
//  - Manages NSPopover containing ContentView
//  - Initializes and manages ClipboardMonitor & DragMonitor
//
// @MainActor is required because it accesses @MainActor objects.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - UI Components
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    // MARK: - Core Monitors
    private let monitor = ClipboardMonitor()
    private var dragMonitor: DragMonitor?

    // MARK: - Auto-Paste State
    // Stores the frontmost application BEFORE the popover opens,
    // so we can return focus to it when performing auto-paste.
    private var previousActiveApp: NSRunningApplication?

    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enable Drag Zone by default on first launch
        UserDefaults.standard.register(defaults: ["dragZoneEnabled": true])

        setupStatusItem()
        setupPopover()
        setupDragZoneIfNeeded()
        observeDragZoneToggle()

        // Hide from Dock and App Switcher
        NSApplication.shared.setActivationPolicy(.accessory)

        // Wire up the auto-paste callback from ClipboardMonitor
        monitor.onAutoPasteRequested = { [weak self] in
            self?.performAutoPaste()
        }
    }

    // MARK: - Setup UI
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard History")
        button.image?.isTemplate = true
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        popover.animates = true

        let contentView = ContentView()
            .environmentObject(monitor)

        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Capture the currently active app BEFORE our popover steals focus.
            // This is the app the user wants to paste into later.
            previousActiveApp = NSWorkspace.shared.frontmostApplication

            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Auto-Paste
    // Called by ClipboardMonitor when the user double-clicks an item.
    // Steps:
    //  1. Close popover
    //  2. Re-activate the app that was frontmost before popover opened
    //  3. Wait briefly for the app to receive focus
    //  4. Simulate Cmd+V to paste from clipboard
    func performAutoPaste() {
        guard checkAccessibilityPermission() else { return }

        popover.performClose(nil)

        if let app = previousActiveApp, !app.isTerminated {
            app.activate(options: [])
        }
        // Even if previousActiveApp is nil or terminated, we still fire the key event —
        // it will target whichever window has focus at that moment.

        // Short delay so the target app has time to become key window before the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.simulateCommandV()
        }
    }

    // Sends a Cmd+V key-down + key-up pair via CGEvent to the HID event tap.
    // 0x09 is the virtual keycode for the V key on all standard keyboard layouts.
    private func simulateCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Accessibility Permission
    // CGEvent key simulation requires Accessibility permission.
    // Returns true if the app is trusted; shows a guidance alert otherwise.
    @discardableResult
    private func checkAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }

        // Not trusted — show a user-friendly alert instead of silently failing.
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            To automatically paste content into other apps, \
            Snip needs Accessibility access.

            Go to System Settings > Privacy & Security > Accessibility \
            and enable Snip.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }

        return false
    }

    // MARK: - Drag Zone Management
    private func setupDragZoneIfNeeded() {
        let enabled = UserDefaults.standard.bool(forKey: "dragZoneEnabled")
        if enabled {
            startDragZone()
        }
    }

    private func observeDragZoneToggle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDragZoneToggle(_:)),
            name: .dragZoneToggled,
            object: nil
        )
    }

    @objc private func handleDragZoneToggle(_ notification: Notification) {
        guard let enabled = notification.object as? Bool else { return }
        if enabled {
            startDragZone()
        } else {
            stopDragZone()
        }
    }

    private func startDragZone() {
        if dragMonitor == nil {
            let dm = DragMonitor()
            dm.onDropReceived = { [weak self] item in
                self?.monitor.addItemFromDrag(item)
            }
            dragMonitor = dm
        }
        dragMonitor?.start()
    }

    private func stopDragZone() {
        dragMonitor?.stop()
        dragMonitor = nil
    }
}
