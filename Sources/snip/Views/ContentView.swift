import AppKit
import SwiftUI

// MARK: - ContentView
// Main UI displayed in NSPopover when clicking the menu bar icon.
// Layout: Search bar -> Item List -> Footer (settings + clear)
struct ContentView: View {

    @EnvironmentObject var monitor: ClipboardMonitor
    @State private var searchText = ""

    // Drag Zone toggle state, saved to UserDefaults
    @AppStorage("dragZoneEnabled") private var dragZoneEnabled = false

    // Auto-Paste toggle: when enabled, double-click will simulate Cmd+V into the previous app.
    // Defaults to true because that is the primary value-add of this feature.
    @AppStorage("autoPasteEnabled") private var autoPasteEnabled = true

    // Temporary feedback state when an item is copied
    @State private var copiedID: UUID? = nil

    // MARK: - Filtered list
    // Pinned items appear first, then unpinned.
    // Filters by searchText if provided.
    var filteredItems: [ClipboardItem] {
        let all = monitor.items

        let filtered: [ClipboardItem]
        if searchText.isEmpty {
            filtered = all
        } else {
            let lower = searchText.lowercased()
            filtered = all.filter { item in
                switch item.type {
                case .text:
                    return item.textContent?.lowercased().contains(lower) ?? false
                case .image:
                    return "image".contains(lower)
                }
            }
        }

        return filtered.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 12) // Space for the arrow
            
            if filteredItems.isEmpty {
                emptyState
            } else {
                itemList
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: AppConstants.popoverWidth, height: AppConstants.popoverHeight + 12, alignment: .top)
        .background(.clear)
        .glassEffect(in: PopoverShape(cornerRadius: AppConstants.popoverCornerRadius))
        .overlay {
            PopoverShape(cornerRadius: AppConstants.popoverCornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.8), .white.opacity(0.1), .white.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(PopoverShape(cornerRadius: AppConstants.popoverCornerRadius))
    }

    // MARK: - Subviews

    private var emptyState: some View {
        Text(searchText.isEmpty ? "No items in history" : "No results found")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredItems) { item in
                    ItemRow(
                        item: item,
                        isCopied: copiedID == item.id,
                        onCopy: { copyItem(item) },
                        onDoubleTap: { doubleTapItem(item) },
                        onOpenLink: { monitor.openLink(item) },
                        onPin: { monitor.togglePin(item: item) },
                        onDelete: { monitor.deleteItem(item) }
                    )
                    Divider()
                        .padding(.leading, 12)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            // Auto-Paste toggle
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Auto-Paste on Double-click")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Requires Accessibility permission")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
                Toggle("", isOn: $autoPasteEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Drag Zone toggle
            HStack {
                Text("Drag Zone")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $dragZoneEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: dragZoneEnabled) { _, newValue in
                        NotificationCenter.default.post(
                            name: .dragZoneToggled,
                            object: newValue
                        )
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            Button(action: { monitor.clearHistory() }) {
                Text("Clear history (keep pinned)")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)

            Divider()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit Snip")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: - Actions
    private func copyItem(_ item: ClipboardItem) {
        monitor.copyToPasteboard(item)
        copiedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == item.id { copiedID = nil }
        }
    }

    private func doubleTapItem(_ item: ClipboardItem) {
        if autoPasteEnabled {
            // Auto-paste: copies to clipboard, closes popover, restores focus, simulates Cmd+V
            monitor.pasteAndGo(item)
        } else {
            // Auto-paste is disabled: treat double-click the same as single-click (copy only)
            copyItem(item)
        }
    }
}

// MARK: - ItemRow
struct ItemRow: View {
    let item: ClipboardItem
    let isCopied: Bool
    let onCopy: () -> Void
    let onDoubleTap: () -> Void
    let onOpenLink: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            contentIcon

            VStack(alignment: .leading, spacing: 3) {
                contentPreview
                    .lineLimit(2)
                    .font(.system(size: 12))

                Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                actionButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: AppConstants.rowCornerRadius)
                .fill(
                    isCopied
                        ? Color.accentColor.opacity(0.15)
                        : isHovered
                            ? Color(NSColor.selectedContentBackgroundColor).opacity(0.08)
                            : Color.clear
                )
        }
        .contentShape(Rectangle())
        // Double-tap MUST be declared before single-tap so SwiftUI can distinguish them.
        // SwiftUI gives priority to the gesture declared first when the same gesture type
        // (tap) appears multiple times; declaring count:2 first prevents it from being
        // swallowed by the count:1 handler.
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture(count: 1) { onCopy() }
        .onHover { isHovered = $0 }
        .overlay(alignment: .topLeading) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
                    .offset(x: 2, y: 2)
            }
        }
        .help("Click to copy · Double-click to paste")
    }

    @ViewBuilder
    private var contentIcon: some View {
        switch item.type {
        case .text:
            // Show link icon only for URL items — plain text needs no icon.
            if item.isLink {
                Image(systemName: "link")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                    .frame(width: 18)
            }
        case .image:
            if let path = item.imagePath,
                let nsImg = NSImage(contentsOfFile: path)
            {
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .text:
            Text(item.previewText)
                .foregroundColor(.primary)
        case .image:
            Text("Image")
                .foregroundColor(.secondary)
                .italic()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            // Open-in-browser button — only shown for link items.
            // Separate from copy (single-click) and auto-paste (double-click).
            if item.isLink {
                Button(action: onOpenLink) {
                    Image(systemName: "safari")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Open in default browser")
            }

            Button(action: onPin) {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
                    .font(.system(size: 11))
                    .foregroundColor(item.isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? "Unpin" : "Pin this item")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Delete this item")
        }
    }
}

extension Notification.Name {
    static let dragZoneToggled = Notification.Name("dragZoneToggled")
}

// MARK: - Custom Popover Shape
// Draws the Liquid Glass popover shape, including the arrow that points to the menu bar icon.
struct PopoverShape: Shape {
    var cornerRadius: CGFloat
    var arrowWidth: CGFloat = 20
    var arrowHeight: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let yStart = arrowHeight
        
        // Start top-left
        path.move(to: CGPoint(x: cornerRadius, y: yStart))
        
        // Arrow
        path.addLine(to: CGPoint(x: rect.midX - arrowWidth / 2, y: yStart))
        path.addLine(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.midX + arrowWidth / 2, y: yStart))
        
        // Top-right corner
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: yStart))
        path.addArc(center: CGPoint(x: rect.width - cornerRadius, y: yStart + cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(0),
                    clockwise: false)
        
        // Bottom-right corner
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - cornerRadius))
        path.addArc(center: CGPoint(x: rect.width - cornerRadius, y: rect.height - cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(0),
                    endAngle: .degrees(90),
                    clockwise: false)
        
        // Bottom-left corner
        path.addLine(to: CGPoint(x: cornerRadius, y: rect.height))
        path.addArc(center: CGPoint(x: cornerRadius, y: rect.height - cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(180),
                    clockwise: false)
        
        // Top-left corner
        path.addLine(to: CGPoint(x: 0, y: yStart + cornerRadius))
        path.addArc(center: CGPoint(x: cornerRadius, y: yStart + cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(270),
                    clockwise: false)
        
        path.closeSubpath()
        return path
    }
}
