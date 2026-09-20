import Foundation

// MARK: - ClipboardItemType
/// The kind of content stored in a clipboard item.
enum ClipboardItemType: String, Codable {
    case text
    case image  // Image is stored on disk; JSON stores only the file path.
}

// MARK: - ClipboardItem
/// A single entry in the clipboard history.
/// Text content is stored inline; images are saved to disk and referenced by path.
struct ClipboardItem: Codable, Identifiable {
    let id: UUID
    let type: ClipboardItemType
    let textContent: String?
    let imagePath: String?
    let timestamp: Date
    var isPinned: Bool
    /// True when the entire text content is a valid URL.
    /// Detected once at item-creation time (never re-computed on every render).
    /// Defaults to false so JSON written before this field existed decodes safely.
    var isLink: Bool = false

    // MARK: - CodingKeys
    // Explicitly list all keys so that `isLink` can carry a default value
    // when decoding old JSON that doesn't contain the field yet.
    enum CodingKeys: String, CodingKey {
        case id, type, textContent, imagePath, timestamp, isPinned, isLink
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,                forKey: .id)
        type        = try c.decode(ClipboardItemType.self,   forKey: .type)
        textContent = try c.decodeIfPresent(String.self,     forKey: .textContent)
        imagePath   = try c.decodeIfPresent(String.self,     forKey: .imagePath)
        timestamp   = try c.decode(Date.self,                forKey: .timestamp)
        isPinned    = try c.decode(Bool.self,                forKey: .isPinned)
        // Missing key → false (backward-compatible with history saved before this feature)
        isLink      = try c.decodeIfPresent(Bool.self,       forKey: .isLink) ?? false
    }

    // MARK: - Initializers
    init(id: UUID, type: ClipboardItemType, textContent: String?,
         imagePath: String?, timestamp: Date, isPinned: Bool, isLink: Bool = false) {
        self.id          = id
        self.type        = type
        self.textContent = textContent
        self.imagePath   = imagePath
        self.timestamp   = timestamp
        self.isPinned    = isPinned
        self.isLink      = isLink
    }

    /// Creates a text clipboard item, optionally marking it as a link.
    static func makeText(_ text: String, isLink: Bool = false) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .text,
            textContent: text,
            imagePath: nil,
            timestamp: Date(),
            isPinned: false,
            isLink: isLink
        )
    }

    /// Creates an image clipboard item referencing the given on-disk file path.
    static func makeImage(path: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .image,
            textContent: nil,
            imagePath: path,
            timestamp: Date(),
            isPinned: false
        )
    }

    // MARK: - UI Preview
    /// A short string suitable for display in the history list row.
    var previewText: String {
        switch type {
        case .text:
            let raw = textContent ?? ""
            return raw.count > AppConstants.textPreviewLength
                ? String(raw.prefix(AppConstants.textPreviewLength)) + "…"
                : raw
        case .image:
            return "Image"
        }
    }
}
