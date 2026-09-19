import Foundation

// MARK: - ClipboardItemType
enum ClipboardItemType: String, Codable {
    case text
    case image  // Image is stored on disk, JSON stores the path
}

// MARK: - ClipboardItem
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
    var previewText: String {
        switch type {
        case .text:
            let raw = textContent ?? ""
            return raw.count > 120 ? String(raw.prefix(120)) + "…" : raw
        case .image:
            return "Image"
        }
    }
}
