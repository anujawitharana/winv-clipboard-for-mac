import Foundation
import AppKit

public struct ClipboardItem: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let contentType: ContentType
    public var plainText: String?
    public var richContent: String?
    public var imageRelativePath: String?
    public var thumbnailRelativePath: String?
    public let timestamp: Date
    public var sourceAppName: String?
    public var sourceAppBundleId: String?
    public var isPinned: Bool
    public let contentHash: String
    public var charCount: Int

    public init(
        id: UUID = UUID(),
        contentType: ContentType,
        plainText: String? = nil,
        richContent: String? = nil,
        imageRelativePath: String? = nil,
        thumbnailRelativePath: String? = nil,
        timestamp: Date = Date(),
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil,
        isPinned: Bool = false,
        contentHash: String,
        charCount: Int = 0
    ) {
        self.id = id
        self.contentType = contentType
        self.plainText = plainText
        self.richContent = richContent
        self.imageRelativePath = imageRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.timestamp = timestamp
        self.sourceAppName = sourceAppName
        self.sourceAppBundleId = sourceAppBundleId
        self.isPinned = isPinned
        self.contentHash = contentHash
        self.charCount = charCount == 0 ? (plainText?.count ?? 0) : charCount
    }

    public var displayTitle: String {
        if let text = plainText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let firstLine = text.components(separatedBy: .newlines).first ?? text
            return String(firstLine.prefix(120))
        }
        switch contentType {
        case .image:
            return "Image"
        case .fileURL:
            if let text = plainText, let url = URL(string: text) {
                return url.lastPathComponent
            }
            return "File"
        case .webURL:
            return plainText ?? "Web Link"
        default:
            return contentType.displayName
        }
    }

    public var previewSnippet: String {
        guard let text = plainText else { return "" }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.prefix(3).joined(separator: " ")
    }

    public var relativeTimeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
