import AppKit
import Foundation

// MARK: - PersistenceManager
/// Handles all file-system operations for Snip:
/// - Reading and writing the clipboard history as JSON
/// - Saving and deleting PNG image files
///
/// Implemented as a caseless enum to serve as a pure namespace —
/// no instance needed, call directly via `PersistenceManager.save(...)`.
///
/// Previously, image-saving logic was duplicated across `ClipboardMonitor`
/// (saveImageToDisk) and `DropTargetView` (saveImageItem) with nearly identical code.
/// Consolidating here means there is one place to change if the storage format ever changes.
enum PersistenceManager {

    // MARK: - Paths

    /// Root directory: ~/Library/Application Support/snip/
    ///
    /// `.first!` is safe here: FileManager always returns at least one URL
    /// for `.applicationSupportDirectory` on macOS — the array is never empty.
    static var appSupportDir: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return base.appendingPathComponent("snip", isDirectory: true)
    }

    /// Path to the JSON file that stores the clipboard history.
    static var jsonFileURL: URL {
        appSupportDir.appendingPathComponent("history.json")
    }

    /// Directory that holds the saved PNG image files.
    static var imagesDir: URL {
        appSupportDir.appendingPathComponent("Images", isDirectory: true)
    }

    // MARK: - Setup

    /// Creates the required directories if they do not already exist.
    /// Call once at app launch before reading or writing any data.
    static func createDirectoriesIfNeeded() {
        do {
            try FileManager.default.createDirectory(
                at: imagesDir,
                withIntermediateDirectories: true
            )
        } catch {
            print("[PersistenceManager] Could not create directories: \(error)")
        }
    }

    // MARK: - JSON Persistence

    /// Encodes `items` to JSON and atomically writes the result to disk.
    static func save(_ items: [ClipboardItem]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(items)
            try data.write(to: jsonFileURL, options: .atomic)
        } catch {
            print("[PersistenceManager] Error saving JSON: \(error)")
        }
    }

    /// Reads the JSON history file from disk and returns the decoded array.
    /// Image items whose backing PNG file no longer exists are silently dropped.
    static func load() -> [ClipboardItem] {
        guard FileManager.default.fileExists(atPath: jsonFileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: jsonFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var items = try decoder.decode([ClipboardItem].self, from: data)

            // Drop image items whose PNG file was deleted outside the app.
            items = items.filter { item in
                if item.type == .image, let path = item.imagePath {
                    return FileManager.default.fileExists(atPath: path)
                }
                return true
            }
            return items
        } catch {
            print("[PersistenceManager] Error loading JSON: \(error)")
            return []
        }
    }

    // MARK: - Image Persistence

    /// Converts `image` to PNG, saves it to the Images directory, and returns the file path.
    /// Returns `nil` if conversion or writing fails.
    static func saveImage(_ image: NSImage) -> String? {
        let fileURL = imagesDir.appendingPathComponent(UUID().uuidString + ".png")

        guard let tiff   = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png    = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try png.write(to: fileURL)
            return fileURL.path
        } catch {
            print("[PersistenceManager] Error saving image: \(error)")
            return nil
        }
    }

    /// Deletes the image file at the given path. Logs an error if deletion fails.
    static func deleteImage(atPath path: String) {
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        } catch {
            print("[PersistenceManager] Error deleting image at \(path): \(error)")
        }
    }
}
