import AppKit
import Foundation

// MARK: - DragMonitor
// Watches system-wide mouse events and shows/hides DragZonePanel accordingly.
//
// WHY use a heuristic (leftMouseDown → leftMouseDragged beyond threshold)?
// macOS exposes no public API that fires exactly when another app starts a
// drag session. NSDraggingDestination only fires AFTER the drag enters our
// view; NSSpringLoadingDestination is for spring-loading; there is no
// "dragDidBeginInForeignApp" notification. The only cross-app signal we can
// observe in real time is raw HID mouse events via NSEvent global monitors.
// So we approximate "drag started" by detecting that the user held the left
// button down and then moved more than a small threshold (~10 pt) — the same
// heuristic the OS itself uses internally to distinguish a click from a drag.
// This is not 100% accurate (e.g. a very slow deliberate drag could miss the
// threshold check on the first event), but it is reliable enough in practice
// and avoids false positives from ordinary clicks.
//
// NOTE: NSEvent.addGlobalMonitorForEvents requires Accessibility permission
// (Privacy & Security > Accessibility). Without it the monitor is silently
// ignored by the system.
@MainActor
final class DragMonitor {

    // MARK: - Public interface
    private(set) var panel: DragZonePanel?
    var onDropReceived: ((ClipboardItem) -> Void)?

    // MARK: - Private state
    private var mouseDownMonitor: Any?
    private var mouseDragMonitor: Any?
    private var mouseUpMonitor: Any?

    /// Location where the last leftMouseDown occurred (screen coordinates).
    private var mouseDownLocation: CGPoint?

    /// Snapshot of NSPasteboard(name: .drag).changeCount taken at mouseDown.
    /// A real OS drag session updates this pasteboard; text selection never does.
    /// Comparing the current count against this snapshot is the reliable way to
    /// distinguish "user is selecting text" from "user is dragging content".
    private var dragPasteboardChangeCount: Int = NSPasteboard(name: .drag).changeCount

    /// True once we have shown the panel for the current drag gesture.
    /// Prevents showing it again on every mouseDragged event.
    private var isPanelVisible = false

    /// True when a successful drop into our panel occurred; suppresses the
    /// automatic hide-on-mouseUp because the panel's own success callback
    /// will trigger the hide after the flash animation finishes.
    private var dropSucceededThisDrag = false

    /// Minimum movement (pt) before we check whether a real drag is happening.
    private let dragThreshold: CGFloat = 10

    // MARK: - Lifecycle

    /// Starts global mouse monitoring. Requires Accessibility permission.
    /// If permission is missing, logs a warning and returns without crashing.
    func start() {
        guard checkAccessibilityPermission() else { return }

        // Create the panel once and reuse it across multiple drags.
        if panel == nil {
            let p = DragZonePanel()
            p.onDropReceived = { [weak self] item in
                // Mark that a successful drop happened so handleMouseUp doesn't
                // race-hide the panel before the 1.3 s success animation finishes.
                self?.dropSucceededThisDrag = true
                self?.onDropReceived?(item)
            }
            // After the 1.3 s success flash the panel hides itself automatically.
            p.onDropSucceeded = { [weak self] in
                self?.dropSucceededThisDrag = false
                self?.isPanelVisible = false
                self?.panel?.hideWithFade()
            }
            panel = p
        }

        installMouseMonitors()
    }

    /// Removes all global monitors and hides the panel.
    func stop() {
        removeMouseMonitors()
        panel?.hideWithFade()
        panel = nil
        isPanelVisible = false
        dropSucceededThisDrag = false
    }

    // MARK: - Global mouse monitor installation

    private func installMouseMonitors() {
        // leftMouseDown — record the click origin so we can measure movement.
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseDown(event)
            }
        }

        // leftMouseDragged — after threshold is crossed, show the panel.
        mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseDragged(event)
            }
        }

        // leftMouseUp — hide the panel if the drop didn't land in our panel.
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseUp(event)
            }
        }
    }

    private func removeMouseMonitors() {
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m); mouseDownMonitor = nil }
        if let m = mouseDragMonitor { NSEvent.removeMonitor(m); mouseDragMonitor = nil }
        if let m = mouseUpMonitor   { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
    }

    // MARK: - Event handlers

    private func handleMouseDown(_ event: NSEvent) {
        // Record click origin for distance measurement.
        mouseDownLocation = convertToScreenPoint(event)
        dropSucceededThisDrag = false
        // Snapshot the drag pasteboard BEFORE any drag starts.
        // A real OS drag session will increment this; text selection will not.
        dragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard !isPanelVisible else { return }       // already visible → nothing to do
        guard let origin = mouseDownLocation else { return }

        // Gate 1 — spatial threshold: ignore tiny cursor jitter.
        let current = convertToScreenPoint(event)
        let dx = current.x - origin.x
        let dy = current.y - origin.y
        guard sqrt(dx * dx + dy * dy) >= dragThreshold else { return }

        // Gate 2 — drag pasteboard check: NSPasteboard(name: .drag) is updated by
        // macOS exactly when an OS-level drag session starts (the source app puts
        // its dragged content onto this shared pasteboard). Text selection never
        // touches this pasteboard, so a changed changeCount means a real drag is
        // in progress — not just the user highlighting some text.
        guard NSPasteboard(name: .drag).changeCount != dragPasteboardChangeCount else { return }

        isPanelVisible = true
        panel?.showWithFade()
    }

    private func handleMouseUp(_ event: NSEvent) {
        mouseDownLocation = nil

        guard isPanelVisible else { return }

        // If the drop landed successfully in our panel, the onDropSucceeded
        // callback already scheduled a hide — don't double-hide.
        if dropSucceededThisDrag { return }

        // The drag ended outside our panel (or the item was rejected).
        // Hide after a short grace period so the user can see the panel was there.
        isPanelVisible = false
        panel?.hideWithFade(delay: 0.15)
    }

    // MARK: - Helpers

    /// Convert an NSEvent's delta-based location to absolute screen coordinates.
    /// NSEvent.mouseLocation gives the current cursor position in screen space.
    private func convertToScreenPoint(_ event: NSEvent) -> CGPoint {
        // NSEvent.mouseLocation is always in screen coordinates (flipped from AppKit).
        return NSEvent.mouseLocation
    }

    // MARK: - Accessibility Check

    /// Returns true if Accessibility is granted, false otherwise.
    /// Logs a clear warning instead of crashing when permission is absent.
    @discardableResult
    private func checkAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }

        print("""
            [DragMonitor] ⚠️  Accessibility permission is NOT granted.
            Global mouse monitoring is disabled — the Drag Zone panel will
            not appear automatically during drags from other apps.
            Grant permission in:
              System Settings > Privacy & Security > Accessibility
            """)
        return false
    }
}
