import Foundation

public enum ContentType: String, Codable, CaseIterable, Sendable {
    case text
    case rtf
    case html
    case image
    case fileURL
    case webURL

    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .rtf: return "Rich Text"
        case .html: return "HTML"
        case .image: return "Image"
        case .fileURL: return "File"
        case .webURL: return "Link"
        }
    }

    public var systemIcon: String {
        switch self {
        case .text: return "doc.text"
        case .rtf: return "doc.richtext"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .fileURL: return "doc"
        case .webURL: return "link"
        }
    }
}
