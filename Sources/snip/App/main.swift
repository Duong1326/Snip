import AppKit

// MARK: - Entry Point
// Swift SPM executable entry point.
// We use NSApplication + AppDelegate instead of @main SwiftUI App
// to create a menu bar app without a Dock icon or main window.

let app = NSApplication.shared

// Hide app from Dock and App Switcher
app.setActivationPolicy(.accessory)
// Initialize AppDelegate on the MainActor
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
}

// Start the AppKit run loop
app.run()
