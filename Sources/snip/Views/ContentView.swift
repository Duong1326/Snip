import SwiftUI
import AppKit

// MARK: - ContentView
// Main UI displayed in NSPopover when clicking the menu bar icon.
// Layout: Search bar -> Item List -> Footer (settings + clear)
struct ContentView: View {

    @EnvironmentObject var monitor: ClipboardMonitor
    @State private var searchText = ""

    // Drag Zone toggle state, saved to UserDefaults
    @AppStorage("dragZoneEnabled") private var dragZoneEnabled = false

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
            searchBar
            Divider()

            if filteredItems.isEmpty {
                emptyState
            } else {
                itemList
            }

            Divider()
            footer
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Subviews
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))

            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clipboard")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "No items in history" : "No results found")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .frame(height: 280)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredItems) { item in
                    ItemRow(
                        item: item,
                        isCopied: copiedID == item.id,
                        onCopy: { copyItem(item) },
                        onPin: { monitor.togglePin(item: item) },
                        onDelete: { monitor.deleteItem(item) }
                    )
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .frame(height: 300)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "arrow.down.to.line.alt")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                Text("Drag Zone")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $dragZoneEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    // Single argument onChange for macOS 13 compatibility
                    .onChange(of: dragZoneEnabled) { newValue in
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
                HStack {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("Clear history (keep pinned)")
                        .font(.system(size: 11))
                }
                .foregroundColor(.red.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
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
}

// MARK: - ItemRow
struct ItemRow: View {
    let item: ClipboardItem
    let isCopied: Bool
    let onCopy: () -> Void
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
        .background(
            Group {
                if isCopied {
                    Color.accentColor.opacity(0.15)
                } else if isHovered {
                    Color(NSColor.selectedContentBackgroundColor).opacity(0.1)
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { onCopy() }
        .onHover { isHovered = $0 }
        .overlay(alignment: .topLeading) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
                    .offset(x: 2, y: 2)
            }
        }
    }

    @ViewBuilder
    private var contentIcon: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 18)
        case .image:
            if let path = item.imagePath,
               let nsImg = NSImage(contentsOfFile: path) {
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
            Text("📷 Image")
                .foregroundColor(.secondary)
                .italic()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
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
