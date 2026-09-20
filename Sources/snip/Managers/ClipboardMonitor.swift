import AppKit
import Foundation

// MARK: - ClipboardMonitor
/// Manages the clipboard history state and lifecycle:
/// - Polls NSPasteboard every 0.5 s to detect new content
/// - Maintains the ordered `items` list published to SwiftUI
/// - Handles pinning, deleting, copying, and auto-paste
/// - Delegates all file I/O to `PersistenceManager`
@MainActor
final class ClipboardMonitor: ObservableObject {

    // MARK: - Published State
    @Published var items: [ClipboardItem] = []

    // MARK: - Polling
    // macOS provides no event-driven API for clipboard changes,
    // so we poll and compare `changeCount` on a timer.
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var pollTimer: Timer?

    // MARK: - Auto-Paste Callback
    // Set by AppDelegate. Called when the user double-clicks an item and
    // auto-paste is enabled. AppDelegate then closes the popover, restores
    // focus to the previous app, and simulates Cmd+V.
    var onAutoPasteRequested: (() -> Void)?

    // MARK: - Auto Clear (Midnight)
    private var dayChangedObserver: Any?

    // MARK: - Init
    init() {
        PersistenceManager.createDirectoriesIfNeeded()
        items = PersistenceManager.load()
        startPolling()
        setupAutoClearAtMidnight()
    }

    // MARK: - Polling

    /// Starts the polling timer that checks NSPasteboard at a fixed interval.
    func startPolling() {
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: AppConstants.pollingInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.checkClipboard() }
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

        // Prioritize images over text when both are present.
        if let image = NSImage(pasteboard: pb) {
            handleNewImage(image)
        } else if let text = pb.string(forType: .string), !text.isEmpty {
            handleNewText(text)
        }
    }

    // MARK: - Handling New Content

    private func handleNewText(_ text: String) {
        // Skip if this text is already the most recent item (written by our own app).
        if let first = items.first, first.type == .text, first.textContent == text { return }
        // Detect URL once at creation time — not on every UI render.
        let item = ClipboardItem.makeText(text, isLink: detectIfURL(text))
        addItem(item)
    }

    private func handleNewImage(_ image: NSImage) {
        guard let path = PersistenceManager.saveImage(image) else { return }
        // Skip if this image is already the most recent item.
        if let first = items.first, first.type == .image, first.imagePath == path { return }
        addItem(ClipboardItem.makeImage(path: path))
    }

    private func addItem(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        trimToLimit()
        PersistenceManager.save(items)
    }

    private func trimToLimit() {
        var unpinnedCount = items.filter { !$0.isPinned }.count
        var i = items.count - 1

        while unpinnedCount > AppConstants.maxHistoryItems && i >= 0 {
            if !items[i].isPinned {
                deleteItemFiles(items[i])
                items.remove(at: i)
                unpinnedCount -= 1
            }
            i -= 1
        }
    }

    // MARK: - Pin / Delete

    /// Toggles the pinned state of the given item and persists the change.
    func togglePin(item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isPinned.toggle()
        PersistenceManager.save(items)
    }

    /// Removes the given item from history and deletes its image file if applicable.
    func deleteItem(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        deleteItemFiles(items[idx])
        items.remove(at: idx)
        PersistenceManager.save(items)
    }

    private func deleteItemFiles(_ item: ClipboardItem) {
        guard item.type == .image, let path = item.imagePath else { return }
        PersistenceManager.deleteImage(atPath: path)
    }

    // MARK: - Copy to Pasteboard

    /// Writes the item's content to NSPasteboard.general, making it the active clipboard.
    func copyToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.type {
        case .text:
            if let text = item.textContent { pb.setString(text, forType: .string) }
        case .image:
            if let path = item.imagePath, let img = NSImage(contentsOfFile: path) {
                pb.writeObjects([img])
            }
        }

        // Sync our change count so the polling loop does not re-add this item.
        lastChangeCount = pb.changeCount
    }

    // MARK: - Auto-Paste (Double-click)

    /// Restores the item to NSPasteboard, then signals AppDelegate to close the popover,
    /// refocus the previous app, and simulate Cmd+V.
    ///
    /// WHY re-write to NSPasteboard even though this content was once there?
    /// NSPasteboard.general only retains the MOST RECENTLY copied content.
    /// When the user copies something after the target item was added, that item
    /// is no longer in the pasteboard. We must restore it as the "current" clipboard
    /// entry before firing Cmd+V; otherwise the destination app would paste whatever
    /// was copied LAST — not the item the user double-clicked.
    func pasteAndGo(_ item: ClipboardItem) {
        copyToPasteboard(item)
        onAutoPasteRequested?()
    }

    // MARK: - Add Item from Drag Zone

    /// Adds an item received from the Drag Zone, skipping it if it duplicates the top item.
    func addItemFromDrag(_ item: ClipboardItem) {
        if let first = items.first,
           first.type == item.type,
           first.textContent == item.textContent,
           first.imagePath == item.imagePath {
            return
        }
        addItem(item)
        lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Link Detection

    /// Returns `true` if `text` (trimmed) is entirely a valid URL.
    ///
    /// Uses NSDataDetector instead of a hand-rolled regex because it is an
    /// Apple-maintained API that correctly handles the full spectrum of URL formats
    /// (with/without scheme, query strings, fragments, IDN hostnames, etc.)
    /// without requiring the caller to maintain a brittle regex pattern.
    func detectIfURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let detector = try? NSDataDetector(
                  types: NSTextCheckingResult.CheckingType.link.rawValue
              ) else { return false }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = detector.firstMatch(in: trimmed, range: range) else { return false }

        // Only mark as a link when the ENTIRE string is the URL —
        // not when a URL appears somewhere inside a longer sentence.
        return match.range.length == trimmed.utf16.count
    }

    /// Prepends `https://` if the URL string has no scheme, so browsers can open it.
    private func normalizeURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://" + trimmed)
    }

    /// Opens the item's URL in the user's default browser.
    /// Does nothing if the item is not a link or the URL is malformed.
    func openLink(_ item: ClipboardItem) {
        guard item.isLink,
              let text = item.textContent,
              let url = normalizeURL(text) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Clear History

    /// Deletes all unpinned items (and their image files) and persists the result.
    func clearHistory() {
        let toDelete = items.filter { !$0.isPinned }
        toDelete.forEach { deleteItemFiles($0) }
        items.removeAll { !$0.isPinned }
        PersistenceManager.save(items)
    }

    // MARK: - Auto Clear (Midnight)

    private func setupAutoClearAtMidnight() {
        // 1. Handle the case where the app was closed overnight: check on startup.
        checkAndClearIfNewDay()

        // 2. Handle the case where the app stays open past midnight.
        dayChangedObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkAndClearIfNewDay() }
        }
    }

    private func checkAndClearIfNewDay() {
        let defaults = UserDefaults.standard
        let lastDateString = defaults.string(forKey: "lastClearDate") ?? ""

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())

        if lastDateString != todayString {
            if !lastDateString.isEmpty {
                // Do not clear on the very first launch (lastDateString is empty).
                // Only clear when the day has changed since the last run.
                clearHistory()
            }
            defaults.set(todayString, forKey: "lastClearDate")
        }
    }
}
