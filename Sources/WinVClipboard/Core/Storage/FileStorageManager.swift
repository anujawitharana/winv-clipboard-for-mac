import Foundation
import AppKit
import ImageIO
import CommonCrypto

public final class FileStorageManager: @unchecked Sendable {
    private let baseDirectory: URL
    private let imagesDirectory: URL
    private let thumbnailsDirectory: URL
    private let queue = DispatchQueue(label: "com.winvclipboard.filestoragemanager", qos: .utility)

    public init(baseDirectory: URL? = nil) {
        if let base = baseDirectory {
            self.baseDirectory = base
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport.appendingPathComponent("WinVClipboard", isDirectory: true)
        }
        self.imagesDirectory = self.baseDirectory.appendingPathComponent("images", isDirectory: true)
        self.thumbnailsDirectory = self.baseDirectory.appendingPathComponent("thumbnails", isDirectory: true)

        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    public var databaseFilePath: String {
        return baseDirectory.appendingPathComponent("clipboard.db").path
    }

    /// Stores image data and generates a small thumbnail.
    /// Returns (imageRelativePath, thumbnailRelativePath)
    public func saveImageData(_ data: Data, contentHash: String) -> (imagePath: String?, thumbnailPath: String?) {
        return queue.sync {
            let ext = "png"
            let imageFilename = "\(contentHash).\(ext)"
            let thumbnailFilename = "\(contentHash)_thumb.\(ext)"

            let imageFileUrl = imagesDirectory.appendingPathComponent(imageFilename)
            let thumbnailFileUrl = thumbnailsDirectory.appendingPathComponent(thumbnailFilename)

            // If original image doesn't exist yet, write it
            if !FileManager.default.fileExists(atPath: imageFileUrl.path) {
                do {
                    try data.write(to: imageFileUrl, options: .atomic)
                } catch {
                    NSLog("Failed to write image data: \(error)")
                    return (nil, nil)
                }
            }

            // If thumbnail doesn't exist yet, generate downsampled version
            if !FileManager.default.fileExists(atPath: thumbnailFileUrl.path) {
                if let thumbData = generateThumbnailData(from: data, maxDimension: 300) {
                    try? thumbData.write(to: thumbnailFileUrl, options: .atomic)
                }
            }

            let imageRelPath = "images/\(imageFilename)"
            let thumbRelPath = "thumbnails/\(thumbnailFilename)"
            return (imageRelPath, thumbRelPath)
        }
    }

    public func fullURL(for relativePath: String) -> URL {
        return baseDirectory.appendingPathComponent(relativePath)
    }

    public func loadThumbnailImage(for relativePath: String) -> NSImage? {
        let url = fullURL(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    public func deleteFile(relativePath: String) {
        queue.sync {
            let url = self.fullURL(for: relativePath)
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func deleteFiles(_ relativePaths: [String?]) {
        queue.sync {
            for rel in relativePaths.compactMap({ $0 }) {
                let url = self.fullURL(for: rel)
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func generateThumbnailData(from data: Data, maxDimension: CGFloat) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]

        guard let cgThumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        let rep = NSBitmapImageRep(cgImage: cgThumbnail)
        return rep.representation(using: .png, properties: [:])
    }
}
