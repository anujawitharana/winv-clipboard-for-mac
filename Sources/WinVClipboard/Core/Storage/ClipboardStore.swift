import Foundation
import AppKit
import Combine

@MainActor
public final class ClipboardStore: ObservableObject {
    public static let shared = ClipboardStore()

    @Published public private(set) var items: [ClipboardItem] = []
    @Published public var searchQuery: String = "" {
        didSet {
            refresh()
        }
    }

    private let dbManager: DatabaseManager
    private let fileManager: FileStorageManager
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var cancellables = Set<AnyCancellable>()

    public init(dbManager: DatabaseManager? = nil, fileManager: FileStorageManager? = nil) {
        let fManager = fileManager ?? FileStorageManager()
        self.fileManager = fManager
        self.dbManager = dbManager ?? DatabaseManager(databasePath: fManager.databaseFilePath)

        thumbnailCache.countLimit = 150
        refresh()
    }

    public func refresh() {
        let currentQuery = searchQuery
        Task.detached(priority: .userInitiated) { [weak self, dbManager] in
            guard let self = self else { return }
            let fetched = dbManager.fetchItems(searchQuery: currentQuery.isEmpty ? nil : currentQuery, limit: 100)
            await MainActor.run {
                self.items = fetched
            }
        }
    }

    public func addOrUpdateItem(
        contentType: ContentType,
        plainText: String?,
        richContent: String?,
        imageData: Data?,
        sourceAppName: String?,
        sourceAppBundleId: String?,
        contentHash: String,
        maxHistoryCount: Int = 50
    ) {
        // Run off main thread
        Task.detached(priority: .userInitiated) { [weak self, dbManager, fileManager] in
            guard let self = self else { return }

            // Check if identical item already exists in DB
            if let existing = dbManager.findItemByHash(contentHash) {
                // Update timestamp so it jumps to top
                dbManager.updateTimestamp(id: existing.id, newTimestamp: Date())
                await self.refresh()
                return
            }

            var imgRelPath: String?
            var thumbRelPath: String?

            if let data = imageData {
                let paths = fileManager.saveImageData(data, contentHash: contentHash)
                imgRelPath = paths.imagePath
                thumbRelPath = paths.thumbnailPath
            }

            let newItem = ClipboardItem(
                id: UUID(),
                contentType: contentType,
                plainText: plainText,
                richContent: richContent,
                imageRelativePath: imgRelPath,
                thumbnailRelativePath: thumbRelPath,
                timestamp: Date(),
                sourceAppName: sourceAppName,
                sourceAppBundleId: sourceAppBundleId,
                isPinned: false,
                contentHash: contentHash,
                charCount: plainText?.count ?? 0
            )

            dbManager.insertOrUpdateItem(newItem)

            // Prune unpinned beyond limit
            let prunedPaths = dbManager.pruneUnpinned(keepMax: maxHistoryCount)
            for pathPair in prunedPaths {
                fileManager.deleteFiles([pathPair.imagePath, pathPair.thumbPath])
            }

            await self.refresh()
        }
    }

    public func togglePin(for item: ClipboardItem) {
        let newPinned = !item.isPinned
        Task.detached(priority: .userInitiated) { [weak self, dbManager] in
            guard let self = self else { return }
            dbManager.setPinned(id: item.id, isPinned: newPinned)
            await self.refresh()
        }
    }

    public func deleteItem(_ item: ClipboardItem) {
        Task.detached(priority: .userInitiated) { [weak self, dbManager, fileManager] in
            guard let self = self else { return }
            let paths = dbManager.deleteItem(id: item.id)
            fileManager.deleteFiles([paths.imagePath, paths.thumbPath])
            await self.refresh()
        }
    }

    public func clearAllUnpinned() {
        Task.detached(priority: .userInitiated) { [weak self, dbManager, fileManager] in
            guard let self = self else { return }
            let deletedPaths = dbManager.clearAllUnpinned()
            for pair in deletedPaths {
                fileManager.deleteFiles([pair.imagePath, pair.thumbPath])
            }
            await self.refresh()
        }
    }

    public func purgeOlderThan(hours: Int) {
        guard hours > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600)).timeIntervalSince1970
        Task.detached(priority: .utility) { [weak self, dbManager, fileManager] in
            guard let self = self else { return }
            let deletedPaths = dbManager.purgeUnpinnedOlderThan(cutoffTimestamp: cutoff)
            for pair in deletedPaths {
                fileManager.deleteFiles([pair.imagePath, pair.thumbPath])
            }
            await self.refresh()
        }
    }

    public func thumbnailImage(for relativePath: String) -> NSImage? {
        let key = relativePath as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        if let loaded = fileManager.loadThumbnailImage(for: relativePath) {
            thumbnailCache.setObject(loaded, forKey: key)
            return loaded
        }
        return nil
    }

    public func fullImage(for relativePath: String) -> NSImage? {
        let url = fileManager.fullURL(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    public func fullImageData(for relativePath: String) -> Data? {
        let url = fileManager.fullURL(for: relativePath)
        return try? Data(contentsOf: url)
    }
}
