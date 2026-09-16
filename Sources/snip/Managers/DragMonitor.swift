import AppKit
import Foundation

// MARK: - DragMonitor
// Manages the DragZonePanel lifecycle.
// No global mouse monitoring or Accessibility permission needed.
// The panel is always visible when the Drag Zone feature is enabled.
@MainActor
final class DragMonitor {

    private(set) var panel: DragZonePanel?
    var onDropReceived: ((ClipboardItem) -> Void)?

    // MARK: - Lifecycle
    func start() {
        if panel == nil {
            let p = DragZonePanel()
            p.onDropReceived = { [weak self] item in
                self?.onDropReceived?(item)
            }
            panel = p
        }
        panel?.showWithFade()
    }

    func stop() {
        panel?.hideWithFade()
        panel = nil
    }
}
