import Foundation

// MARK: - ClipboardItemType
enum ClipboardItemType: String, Codable {
    case text
    case image // Image is stored on disk, JSON stores the path
}

// MARK: - ClipboardItem
struct ClipboardItem: Codable, Identifiable {
    let id: UUID
    let type: ClipboardItemType
    let textContent: String?
    let imagePath: String?
    let timestamp: Date
    var isPinned: Bool

    // MARK: Initializers
    static func makeText(_ text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .text,
            textContent: text,
            imagePath: nil,
            timestamp: Date(),
            isPinned: false
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
            return "📷 Image"
        }
    }
}
