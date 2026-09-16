import AppKit

// MARK: - DragZonePanel
// Persistent floating NSPanel that accepts drag-and-drop from any app.
// Always visible (no Accessibility permission required).
// Designed as a frosted-glass square pinned to the bottom-right corner.
final class DragZonePanel: NSPanel {

    var onDropReceived: ((ClipboardItem) -> Void)?
    private var dropView: DropTargetView!

    // MARK: - Init
    init() {
        let size = NSSize(width: 110, height: 110)
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
    }

    private func setupDropView() {
        dropView = DropTargetView(frame: NSRect(x: 0, y: 0, width: 110, height: 110))
        dropView.onDropReceived = { [weak self] item in
            self?.onDropReceived?(item)
        }
        self.contentView = dropView
    }

    private func positionAtBottomRight() {
        guard let screen = NSScreen.main else { return }
        let sv = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(NSPoint(
            x: sv.maxX - size.width - 20,
            y: sv.minY + 20
        ))
    }

    // MARK: - Show / Hide
    func showWithFade() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 1.0
        }
    }

    func hideWithFade(delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                self?.animator().alphaValue = 0
            }, completionHandler: {
                self?.orderOut(nil)
            })
        }
    }
}

// MARK: - DropTargetView
// Frosted-glass drop target with 3 visual states.
final class DropTargetView: NSView {

    var onDropReceived: ((ClipboardItem) -> Void)?

    // MARK: - State
    enum DropState { case idle, hovering, success }

    private var state: DropState = .idle {
        didSet {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
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
            borderColor  = NSColor.white.withAlphaComponent(0.22)
            icon  = "📋"
            label = "Drag\nZone"
        case .hovering:
            overlayColor = NSColor.systemBlue.withAlphaComponent(0.38)
            borderColor  = NSColor.systemBlue.withAlphaComponent(0.90)
            icon  = "⬇️"
            label = "Drop\nHere"
        case .success:
            overlayColor = NSColor.systemGreen.withAlphaComponent(0.38)
            borderColor  = NSColor.systemGreen.withAlphaComponent(0.90)
            icon  = "✅"
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
        iconStr.draw(at: NSPoint(
            x: (b.width - iconSize.width) / 2,
            y: b.height * 0.52 + 2
        ))

        // ---- Label ----
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(state == .idle ? 0.75 : 1.0),
            .paragraphStyle: para
        ]
        let labelStr = NSAttributedString(string: label, attributes: labelAttr)
        let labelSize = labelStr.size()
        labelStr.draw(at: NSPoint(
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
           let item = saveImageItem(image) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            flashSuccess { [weak self] in self?.onDropReceived?(item) }
            return true
        }

        // --- Image (PNG fallback) ---
        let pngType = NSPasteboard.PasteboardType("public.png")
        if let imgData = pb.data(forType: pngType),
           let image = NSImage(data: imgData),
           let item = saveImageItem(image) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            self?.state = .idle
        }
    }

    private func saveImageItem(_ image: NSImage) -> ClipboardItem? {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let imagesDir = base.appendingPathComponent("snip/Images", isDirectory: true)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let fileURL = imagesDir.appendingPathComponent(UUID().uuidString + ".png")

        guard let tiff   = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png    = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        do {
            try png.write(to: fileURL)
            return ClipboardItem.makeImage(path: fileURL.path)
        } catch {
            print("[DragZone] Failed to save image: \(error)")
            return nil
        }
    }
}
