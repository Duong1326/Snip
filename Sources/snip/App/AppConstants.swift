import CoreGraphics
import Foundation

/// Constants for the Snip application.
enum AppConstants {

    // MARK: - Clipboard History

    /// Maximum number of items to keep in history.
    static let maxHistoryItems = 200

    /// Interval in seconds between each NSPasteboard check.
    static let pollingInterval: TimeInterval = 0.5

    /// Maximum number of characters to display in the preview row of a text item.
    static let textPreviewLength = 120

    // MARK: - Auto-Paste

    static let autoPasteDelay: TimeInterval = 0.1

    // MARK: - Popover

    static let popoverWidth: CGFloat = 320
    static let popoverHeight: CGFloat = 420

    // MARK: - Drag Zone Panel

    static let dragZonePanelSize: CGFloat = 200
    static let dragZoneMargin: CGFloat = 20

    // MARK: - Drag Detection

    static let dragThreshold: CGFloat = 10

    // MARK: - Animations

    static let panelShowDuration: TimeInterval = 1.0

    static let panelHideDuration: TimeInterval = 0.2

    static let successFlashDuration: TimeInterval = 1.3

    static let stateTransitionDuration: TimeInterval = 0.15

    // MARK: - Glass

    /// Corner radius of the main popover glass container.
    static let popoverCornerRadius: CGFloat = 12

    /// Corner radius for interactive row hover highlights.
    static let rowCornerRadius: CGFloat = 8
}
