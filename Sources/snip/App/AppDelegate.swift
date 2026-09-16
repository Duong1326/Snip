import AppKit
import SwiftUI

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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
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
