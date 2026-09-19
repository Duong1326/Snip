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

    // MARK: - Auto-Paste Callback
    // Set by AppDelegate. Called when the user double-clicks an item and
    // auto-paste is enabled. AppDelegate then closes the popover, restores
    // focus to the previous app, and simulates Cmd+V.
    var onAutoPasteRequested: (() -> Void)?

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

    // MARK: - Auto Clear (Midnight)
    private var dayChangedObserver: Any?

    // MARK: - Init
    init() {
        createDirectoriesIfNeeded()
        loadFromDisk()
        startPolling()
        setupAutoClearAtMidnight()
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
        // Detect once at creation time — never re-detect on every UI render.
        let item = ClipboardItem.makeText(text, isLink: detectIfURL(text))
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

        // Update our own change count so the polling loop doesn't re-add this as a new item.
        lastChangeCount = pb.changeCount
    }

    // MARK: - Auto-Paste (Double-click)
    // Writes the selected item back into NSPasteboard.general, then triggers
    // the AppDelegate to close the popover, restore focus, and simulate Cmd+V.
    //
    // WHY re-write to NSPasteboard even though this content was once there?
    // NSPasteboard.general only retains the MOST RECENTLY copied content.
    // When the user copies something after the target item was added, that item
    // is no longer in the pasteboard. We must restore it as the "current" clipboard
    // entry before firing Cmd+V; otherwise the destination app would paste whatever
    // was copied LAST — not the item the user double-clicked.
    func pasteAndGo(_ item: ClipboardItem) {
        // Step 1: Restore this item as the active clipboard content.
        copyToPasteboard(item)

        // Step 2: Delegate the popover-close + focus-restore + key-simulation to AppDelegate.
        onAutoPasteRequested?()
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

    // MARK: - Link Detection

    // NSDataDetector is used instead of a hand-rolled regex because it is an
    // Apple-maintained API that correctly handles the full spectrum of URL formats
    // (with/without scheme, query strings, fragments, IDN hostnames, etc.) without
    // requiring the caller to maintain a brittle regex pattern.
    func detectIfURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let detector = try? NSDataDetector(
                  types: NSTextCheckingResult.CheckingType.link.rawValue
              ) else { return false }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = detector.firstMatch(in: trimmed, range: range) else { return false }

        // Only mark as link when the ENTIRE string is the URL — not when a URL
        // appears inside a longer sentence.
        return match.range.length == trimmed.utf16.count
    }

    /// Ensures the URL has a scheme so browsers and NSWorkspace can open it.
    /// "google.com" → "https://google.com"
    private func normalizeURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://" + trimmed)
    }

    /// Opens the item's URL in the user's default browser via NSWorkspace.
    /// Does nothing (no crash) if the item is not a link or the URL is malformed.
    func openLink(_ item: ClipboardItem) {
        guard item.isLink,
              let text = item.textContent,
              let url = normalizeURL(text) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Clear History
    func clearHistory() {
        let toDelete = items.filter { !$0.isPinned }
        toDelete.forEach { deleteItemFiles($0) }
        items.removeAll { !$0.isPinned }
        saveToDisk()
    }

    // MARK: - Auto Clear (Midnight)

    private func setupAutoClearAtMidnight() {
        // 1. Check if the app was closed overnight and clean up on startup
        checkAndClearIfNewDay()

        // 2. If the app is open and running overnight, clean up right at midnight
        dayChangedObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkAndClearIfNewDay()
        }
    }

    private func checkAndClearIfNewDay() {
        let defaults = UserDefaults.standard
        let lastDateString = defaults.string(forKey: "lastClearDate") ?? ""
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())
        
        if lastDateString != todayString {
            // It's a new day since the last check
            if !lastDateString.isEmpty {
                // Do not clear on the VERY FIRST launch (when lastDateString is empty)
                // Only clear when crossing over from a previous day
                clearHistory()
            }
            defaults.set(todayString, forKey: "lastClearDate")
        }
    }
}
