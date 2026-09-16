import AppKit
import Foundation

// MARK: - ClipboardMonitor
// Manages clipboard history lifecycle:
//  - Polls NSPasteboard for changes
//  - Reads/writes JSON metadata to disk
//  - Saves images to separate PNG files
//  - Handles pinning, deleting, and copying items
@MainActor
final class ClipboardMonitor: ObservableObject {

    // MARK: - Published state
    @Published var items: [ClipboardItem] = []

    // MARK: - Constants
    private let maxItems = 200 // Excludes pinned items

    // MARK: - Polling
    // macOS doesn't provide an event-driven API for clipboard changes,
    // so we poll and compare `changeCount`.
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var pollTimer: Timer?

    // MARK: - Storage Paths
    private var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("snip", isDirectory: true)
    }

    private var jsonFileURL: URL {
        appSupportDir.appendingPathComponent("history.json")
    }

    private var imagesDir: URL {
        appSupportDir.appendingPathComponent("Images", isDirectory: true)
    }

    // MARK: - Init
    init() {
        createDirectoriesIfNeeded()
        loadFromDisk()
        startPolling()
    }

    // MARK: - Polling
    func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Prioritize images over text
        if let image = NSImage(pasteboard: pb) {
            handleNewImage(image)
        } else if let text = pb.string(forType: .string), !text.isEmpty {
            handleNewText(text)
        }
    }

    // MARK: - Handling New Content
    private func handleNewText(_ text: String) {
        // Prevent duplicates from our own app
        if let first = items.first, first.type == .text, first.textContent == text {
            return
        }
        let item = ClipboardItem.makeText(text)
        addItem(item)
    }

    private func handleNewImage(_ image: NSImage) {
        guard let path = saveImageToDisk(image) else { return }

        // Prevent duplicates
        if let first = items.first, first.type == .image, first.imagePath == path {
            return
        }
        let item = ClipboardItem.makeImage(path: path)
        addItem(item)
    }

    private func addItem(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        trimToLimit()
        saveToDisk()
    }

    private func trimToLimit() {
        var unpinnedCount = items.filter { !$0.isPinned }.count
        var i = items.count - 1
        
        while unpinnedCount > maxItems && i >= 0 {
            if !items[i].isPinned {
                deleteItemFiles(items[i])
                items.remove(at: i)
                unpinnedCount -= 1
            }
            i -= 1
        }
    }

    // MARK: - Pin / Delete
    func togglePin(item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isPinned.toggle()
        saveToDisk()
    }

    func deleteItem(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        deleteItemFiles(items[idx])
        items.remove(at: idx)
        saveToDisk()
    }

    private func deleteItemFiles(_ item: ClipboardItem) {
        guard item.type == .image, let path = item.imagePath else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Copy to Pasteboard
    func copyToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.type {
        case .text:
            if let text = item.textContent {
                pb.setString(text, forType: .string)
            }
        case .image:
            if let path = item.imagePath,
               let img = NSImage(contentsOfFile: path) {
                pb.writeObjects([img])
            }
        }

        lastChangeCount = pb.changeCount
    }

    // MARK: - Image Storage
    private func saveImageToDisk(_ image: NSImage) -> String? {
        let filename = UUID().uuidString + ".png"
        let fileURL = imagesDir.appendingPathComponent(filename)

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try png.write(to: fileURL)
            return fileURL.path
        } catch {
            print("[ClipboardMonitor] Error saving image: \(error)")
            return nil
        }
    }

    // MARK: - Persistence (JSON)
    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(items)
            try data.write(to: jsonFileURL, options: .atomic)
        } catch {
            print("[ClipboardMonitor] Error saving JSON: \(error)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: jsonFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: jsonFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([ClipboardItem].self, from: data)

            // Remove image items if the corresponding file no longer exists
            items = items.filter { item in
                if item.type == .image, let path = item.imagePath {
                    return FileManager.default.fileExists(atPath: path)
                }
                return true
            }
        } catch {
            print("[ClipboardMonitor] Error reading JSON: \(error)")
            items = []
        }
    }

    // MARK: - Add Item from Drag Zone
    func addItemFromDrag(_ item: ClipboardItem) {
        if let first = items.first {
            if first.type == item.type &&
               first.textContent == item.textContent &&
               first.imagePath == item.imagePath {
                return
            }
        }
        addItem(item)
        lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Clear History
    func clearHistory() {
        let toDelete = items.filter { !$0.isPinned }
        toDelete.forEach { deleteItemFiles($0) }
        items.removeAll { !$0.isPinned }
        saveToDisk()
    }
}
