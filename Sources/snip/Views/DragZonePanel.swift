import AppKit

// MARK: - DragZonePanel
// Floating NSPanel that accepts drag-and-drop from any app.
// Hidden by default; DragMonitor calls showWithFade() when it detects a
// drag gesture on the system, and hideWithFade() when the drag ends.
// Designed as a frosted-glass square pinned to the bottom-right corner.
final class DragZonePanel: NSPanel {

    var onDropReceived: ((ClipboardItem) -> Void)?
    /// Called by DropTargetView after the success animation finishes (~1.3 s).
    /// DragMonitor uses this to hide the panel automatically.
    var onDropSucceeded: (() -> Void)?
    private var dropView: DropTargetView!

    // Cached destination frame set once by positionAtBottomRight().
    // showWithFade() MUST read from this stored value — NOT from self.frame —
    // because self.frame may be 0×0 mid-animation from a previous show cycle,
    // which would make every drag after the first one invisible.
    private var panelTargetFrame: NSRect = .zero

    // MARK: - Init
    init() {
        let size = NSSize(
            width: AppConstants.dragZonePanelSize,
            height: AppConstants.dragZonePanelSize
        )
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovableByWindowBackground = true
        self.hasShadow = true

        setupDropView()
        positionAtBottomRight()
        // Panel starts hidden; DragMonitor shows it when a drag is detected.
        // orderOut keeps it completely inert (no hit-testing, no compositing cost).
    }

    private func setupDropView() {
        let panelSize = frame.size
        dropView = DropTargetView(frame: NSRect(origin: .zero, size: panelSize))
        dropView.onDropReceived = { [weak self] item in
            self?.onDropReceived?(item)
        }
        dropView.onDropSucceeded = { [weak self] in
            // Forward to DragMonitor so it can hide the panel after the success flash.
            self?.onDropSucceeded?()
        }
        self.contentView = dropView
    }

    private func positionAtBottomRight() {
        guard let screen = NSScreen.main else { return }
        let sv = screen.visibleFrame
        // Read size from the current frame (still intact at init time, before any animation).
        let size = frame.size
        let margin = AppConstants.dragZoneMargin
        let origin = NSPoint(x: sv.maxX - size.width - margin, y: sv.minY + margin)
        setFrameOrigin(origin)
        // Cache the correct full-size frame for use in showWithFade().
        panelTargetFrame = NSRect(origin: origin, size: size)
    }

    // MARK: - Show / Hide
    func showWithFade() {
        // Use the cached target frame — never read self.frame here because
        // it may still be 0×0 leftover from the startFrame set during a
        // previous animation cycle, causing the panel to stay invisible.
        let targetFrame = panelTargetFrame
        guard targetFrame != .zero else { return }

        // Start collapsed to a zero-size point anchored at the bottom-right corner
        // so the panel "blooms" outward from the corner rather than flying in.
        let startFrame = NSRect(
            x: targetFrame.maxX,
            y: targetFrame.minY,
            width: 0,
            height: 0
        )
        setFrame(startFrame, display: false)
        alphaValue = 0
        orderFront(nil)

        // Animate size and opacity together.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppConstants.panelShowDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 1.0
        }
    }

    func hideWithFade(delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            NSAnimationContext.runAnimationGroup(
                { ctx in
                    ctx.duration = AppConstants.panelHideDuration
                    self?.animator().alphaValue = 0
                },
                completionHandler: {
                    MainActor.assumeIsolated {
                        self?.orderOut(nil)
                    }
                })
        }
    }
}

// MARK: - DropTargetView
// Frosted-glass drop target with 3 visual states.
final class DropTargetView: NSView {

    var onDropReceived: ((ClipboardItem) -> Void)?
    /// Fired after the 1.3 s success flash, signalling DragMonitor to hide the panel.
    var onDropSucceeded: (() -> Void)?

    // MARK: - State
    enum DropState { case idle, hovering, success }

    private var state: DropState = .idle {
        didSet {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = AppConstants.stateTransitionDuration
                self.needsDisplay = true
            }
        }
    }

    // MARK: - Init
    override init(frame: NSRect) {
        super.init(frame: frame)

        // Blur background
        let blur = NSVisualEffectView(frame: bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 22
        blur.layer?.masksToBounds = true
        addSubview(blur)

        // Register accepted drag types
        let pngType = NSPasteboard.PasteboardType("public.png")
        registerForDraggedTypes([.string, .fileURL, .tiff, pngType])

        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let b = bounds
        let radius: CGFloat = 22

        // Overlay color
        let (overlayColor, borderColor, icon, label): (NSColor, NSColor, String, String)
        switch state {
        case .idle:
            overlayColor = NSColor.black.withAlphaComponent(0.28)
            borderColor = NSColor.white.withAlphaComponent(0.22)
            icon = "📋"
            label = "Drag\nZone"
        case .hovering:
            overlayColor = NSColor.systemBlue.withAlphaComponent(0.38)
            borderColor = NSColor.systemBlue.withAlphaComponent(0.90)
            icon = "⬇️"
            label = "Drop\nHere"
        case .success:
            overlayColor = NSColor.systemGreen.withAlphaComponent(0.38)
            borderColor = NSColor.systemGreen.withAlphaComponent(0.90)
            icon = "✅"
            label = "Saved!"
        }

        // Fill overlay
        overlayColor.setFill()
        NSBezierPath(roundedRect: b, xRadius: radius, yRadius: radius).fill()

        // Border
        borderColor.setStroke()
        let borderPath = NSBezierPath(
            roundedRect: b.insetBy(dx: 1.5, dy: 1.5),
            xRadius: radius - 1,
            yRadius: radius - 1
        )
        borderPath.lineWidth = state == .idle ? 1.5 : 2.0
        borderPath.stroke()

        // ---- Icon ----
        let iconAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28)]
        let iconStr = NSAttributedString(string: icon, attributes: iconAttr)
        let iconSize = iconStr.size()
        iconStr.draw(
            at: NSPoint(
                x: (b.width - iconSize.width) / 2,
                y: b.height * 0.52 + 2
            ))

        // ---- Label ----
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(state == .idle ? 0.75 : 1.0),
            .paragraphStyle: para,
        ]
        let labelStr = NSAttributedString(string: label, attributes: labelAttr)
        let labelSize = labelStr.size()
        labelStr.draw(
            at: NSPoint(
                x: (b.width - labelSize.width) / 2,
                y: b.height * 0.52 - labelSize.height - 4
            ))
    }

    // MARK: - NSDraggingDestination
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        state = .hovering
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        state = .idle
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard

        // --- Text ---
        if let text = pb.string(forType: .string), !text.isEmpty {
            let item = ClipboardItem.makeText(text)
            // Write to system clipboard immediately
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            flashSuccess { [weak self] in self?.onDropReceived?(item) }
            return true
        }

        // --- Image (TIFF) ---
        if let imgData = pb.data(forType: .tiff),
            let image = NSImage(data: imgData),
            let item = makeImageItem(from: image)
        {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            flashSuccess { [weak self] in self?.onDropReceived?(item) }
            return true
        }

        // --- Image (PNG fallback) ---
        let pngType = NSPasteboard.PasteboardType("public.png")
        if let imgData = pb.data(forType: pngType),
            let image = NSImage(data: imgData),
            let item = makeImageItem(from: image)
        {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            flashSuccess { [weak self] in self?.onDropReceived?(item) }
            return true
        }

        state = .idle
        return false
    }

    // MARK: - Helpers

    private func flashSuccess(completion: @escaping () -> Void) {
        state = .success
        completion()
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.successFlashDuration) { [weak self] in
            self?.state = .idle
            // Notify DragMonitor that the success animation is done so it can hide the panel.
            // Reset to .idle first so the panel looks correct on the next drag.
            self?.onDropSucceeded?()
        }
    }

    /// Saves `image` to disk via PersistenceManager and wraps the result in a ClipboardItem.
    private func makeImageItem(from image: NSImage) -> ClipboardItem? {
        guard let path = PersistenceManager.saveImage(image) else { return nil }
        return ClipboardItem.makeImage(path: path)
    }
}
