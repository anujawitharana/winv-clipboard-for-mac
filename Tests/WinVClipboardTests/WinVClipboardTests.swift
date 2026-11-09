import XCTest
import AppKit
import Carbon
@testable import WinVClipboard

final class WinVClipboardTests: XCTestCase {
    var tempDirectory: URL!
    var dbManager: DatabaseManager!
    var fileManager: FileStorageManager!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let dbPath = tempDirectory.appendingPathComponent("test_clipboard.db").path
        dbManager = DatabaseManager(databasePath: dbPath)
        fileManager = FileStorageManager(baseDirectory: tempDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testDatabaseInsertAndFetch() {
        let item1 = ClipboardItem(
            id: UUID(),
            contentType: .text,
            plainText: "Hello world 1",
            contentHash: "hash1"
        )
        let item2 = ClipboardItem(
            id: UUID(),
            contentType: .text,
            plainText: "Special keyword clip",
            contentHash: "hash2"
        )

        dbManager.insertOrUpdateItem(item1)
        dbManager.insertOrUpdateItem(item2)

        let allItems = dbManager.fetchItems(limit: 10)
        XCTAssertEqual(allItems.count, 2)

        let searchItems = dbManager.fetchItems(searchQuery: "keyword", limit: 10)
        XCTAssertEqual(searchItems.count, 1)
        XCTAssertEqual(searchItems.first?.plainText, "Special keyword clip")
    }

    func testPinningPreservedAcrossClearAll() {
        let unpinned = ClipboardItem(
            id: UUID(),
            contentType: .text,
            plainText: "Temporary note",
            isPinned: false,
            contentHash: "unpinned_hash"
        )
        let pinned = ClipboardItem(
            id: UUID(),
            contentType: .text,
            plainText: "Crucial permanent clip",
            isPinned: true,
            contentHash: "pinned_hash"
        )

        dbManager.insertOrUpdateItem(unpinned)
        dbManager.insertOrUpdateItem(pinned)

        let initial = dbManager.fetchItems(limit: 10)
        XCTAssertEqual(initial.count, 2)

        _ = dbManager.clearAllUnpinned()

        let remaining = dbManager.fetchItems(limit: 10)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.plainText, "Crucial permanent clip")
        XCTAssertTrue(remaining.first?.isPinned == true)
    }

    func testPruningRetainsPinnedAndLimitsUnpinned() {
        // Insert 10 unpinned items
        for i in 1...10 {
            let item = ClipboardItem(
                id: UUID(),
                contentType: .text,
                plainText: "Unpinned \(i)",
                timestamp: Date().addingTimeInterval(Double(i)),
                isPinned: false,
                contentHash: "hash_unpinned_\(i)"
            )
            dbManager.insertOrUpdateItem(item)
        }

        // Insert 2 pinned items
        for i in 1...2 {
            let item = ClipboardItem(
                id: UUID(),
                contentType: .text,
                plainText: "Pinned \(i)",
                timestamp: Date().addingTimeInterval(Double(i)),
                isPinned: true,
                contentHash: "hash_pinned_\(i)"
            )
            dbManager.insertOrUpdateItem(item)
        }

        // Keep maximum 5 unpinned
        _ = dbManager.pruneUnpinned(keepMax: 5)

        let items = dbManager.fetchItems(limit: 50)
        let unpinnedCount = items.filter { !$0.isPinned }.count
        let pinnedCount = items.filter { $0.isPinned }.count

        XCTAssertEqual(unpinnedCount, 5)
        XCTAssertEqual(pinnedCount, 2)
        XCTAssertEqual(items.count, 7)
    }

    func testFileStorageAndThumbnails() {
        // Generate a 100x100 test image representation
        let img = NSImage(size: NSSize(width: 100, height: 100))
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        img.unlockFocus()

        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create test PNG data")
            return
        }

        let paths = fileManager.saveImageData(png, contentHash: "sample_img_hash")
        XCTAssertNotNil(paths.imagePath)
        XCTAssertNotNil(paths.thumbnailPath)

        let thumb = fileManager.loadThumbnailImage(for: paths.thumbnailPath!)
        XCTAssertNotNil(thumb)

        fileManager.deleteFiles([paths.imagePath, paths.thumbnailPath])
        let deletedThumb = fileManager.loadThumbnailImage(for: paths.thumbnailPath!)
        XCTAssertNil(deletedThumb)
    }

    func testPrivacyFilterExclusions() {
        let filter = PrivacyFilter()

        // 1. Password manager bundle ID should be blocked
        XCTAssertTrue(filter.allExcludedBundleIDs().contains("com.1password.1password"))
        XCTAssertTrue(filter.allExcludedBundleIDs().contains("com.apple.keychainaccess"))

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.test.pasteboard.\(UUID().uuidString)"))
        XCTAssertTrue(filter.shouldIgnore(pasteboard: pasteboard, sourceBundleID: "com.1password.1password"))

        // 2. Custom exclusion
        filter.addExcludedBundleID("com.custom.secretapp")
        XCTAssertTrue(filter.shouldIgnore(pasteboard: pasteboard, sourceBundleID: "com.custom.secretapp"))

        filter.removeExcludedBundleID("com.custom.secretapp")
        XCTAssertFalse(filter.allExcludedBundleIDs().contains("com.custom.secretapp"))

        // 3. Concealed types
        pasteboard.declareTypes([NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        XCTAssertTrue(filter.shouldIgnore(pasteboard: pasteboard, sourceBundleID: "com.apple.Safari"))
    }

    func testKeyComboFormattingAndConflicts() {
        let defaultCombo = KeyCombo.defaultShortcut
        XCTAssertEqual(defaultCombo.displayString, "⌥V")
        XCTAssertFalse(defaultCombo.isSystemReservedConflict)

        // Conflict check for standard Cmd+C
        let cmdC = KeyCombo(keyCode: 0x08 /* C */, carbonModifiers: UInt32(cmdKey))
        XCTAssertTrue(cmdC.isSystemReservedConflict)

        // Custom shortcut Cmd+Shift+V
        let custom = KeyCombo(keyCode: 0x09 /* V */, carbonModifiers: UInt32(cmdKey | shiftKey))
        XCTAssertEqual(custom.displayString, "⇧⌘V")
        XCTAssertFalse(custom.isSystemReservedConflict)
    }

    @MainActor
    func testStoreKeyboardNavigationAndSelection() {
        let store = ClipboardStore(dbManager: dbManager, fileManager: fileManager)

        let item1 = ClipboardItem(id: UUID(), contentType: .text, plainText: "Item 1", timestamp: Date().addingTimeInterval(3), contentHash: "h1")
        let item2 = ClipboardItem(id: UUID(), contentType: .text, plainText: "Item 2", timestamp: Date().addingTimeInterval(2), contentHash: "h2")
        let item3 = ClipboardItem(id: UUID(), contentType: .text, plainText: "Item 3", timestamp: Date().addingTimeInterval(1), contentHash: "h3")

        dbManager.insertOrUpdateItem(item1)
        dbManager.insertOrUpdateItem(item2)
        dbManager.insertOrUpdateItem(item3)

        store.refreshSync()

        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.selectedItemId, item1.id)

        // Navigation down: item1 -> item2
        store.selectNext()
        XCTAssertEqual(store.selectedItemId, item2.id)

        // Navigation down: item2 -> item3
        store.selectNext()
        XCTAssertEqual(store.selectedItemId, item3.id)

        // Clamping at boundary
        store.selectNext()
        XCTAssertEqual(store.selectedItemId, item3.id)

        // Navigation up: item3 -> item2
        store.selectPrevious()
        XCTAssertEqual(store.selectedItemId, item2.id)

        // Navigation up: item2 -> item1
        store.selectPrevious()
        XCTAssertEqual(store.selectedItemId, item1.id)

        // Clamping at top
        store.selectPrevious()
        XCTAssertEqual(store.selectedItemId, item1.id)
    }

    func testImageFileDetectionAndPreview() {
        // Create a temporary PNG image file on disk
        let imageFileURL = tempDirectory.appendingPathComponent("test_screenshot.png")
        let img = NSImage(size: NSSize(width: 200, height: 150))
        img.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 150).fill()
        img.unlockFocus()

        let tiff = img.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        let pngData = rep.representation(using: .png, properties: [:])!
        try? pngData.write(to: imageFileURL)

        // Save image via FileStorageManager
        let paths = fileManager.saveImageData(pngData, contentHash: "screenshot_hash")
        XCTAssertNotNil(paths.thumbnailPath)

        let item = ClipboardItem(
            id: UUID(),
            contentType: .image,
            plainText: imageFileURL.path,
            imageRelativePath: paths.imagePath,
            thumbnailRelativePath: paths.thumbnailPath,
            contentHash: "screenshot_hash"
        )
        dbManager.insertOrUpdateItem(item)

        let fetched = dbManager.fetchItems(limit: 5)
        XCTAssertEqual(fetched.first?.contentType, .image)
        XCTAssertEqual(fetched.first?.plainText, imageFileURL.path)
        XCTAssertNotNil(fetched.first?.thumbnailRelativePath)

        let thumb = fileManager.loadThumbnailImage(for: fetched.first!.thumbnailRelativePath!)
        XCTAssertNotNil(thumb)
    }

    func testSQLiteTextBindingWithComplexAndTransientStrings() {
        let specialText = """
        🚀 Swift Concurrency & SQLite3:
        Quotes: "Hello 'world'", `backticks`, \n Newline with \\ backslash.
        SQL Injection string: '); DROP TABLE clipboard_items; --
        Math: 2 + 2 = 4, ∑(x_i)
        """

        let item = ClipboardItem(
            id: UUID(),
            contentType: .text,
            plainText: specialText,
            richContent: "<b>Rich</b> content with 'quotes'",
            sourceAppName: "Safari 🧭",
            sourceAppBundleId: "com.apple.Safari",
            contentHash: "special_hash"
        )

        dbManager.insertOrUpdateItem(item)

        let fetched = dbManager.fetchItems(limit: 5)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.plainText, specialText)
        XCTAssertEqual(fetched.first?.richContent, "<b>Rich</b> content with 'quotes'")
        XCTAssertEqual(fetched.first?.sourceAppName, "Safari 🧭")
    }

    func testDatabaseRecoveryWithWALAndSHMCleanup() {
        let dbPath = tempDirectory.appendingPathComponent("test_recovery.db").path
        let manager = DatabaseManager(databasePath: dbPath)

        let item = ClipboardItem(
            id: UUID(),
            contentType: .text,
            plainText: "Pre-recovery item",
            contentHash: "pre_hash"
        )
        manager.insertOrUpdateItem(item)

        // Ensure WAL file is created by performing a write
        let walPath = dbPath + "-wal"
        let shmPath = dbPath + "-shm"
        // Touch WAL/SHM if not yet flushed
        if !FileManager.default.fileExists(atPath: walPath) {
            FileManager.default.createFile(atPath: walPath, contents: Data("wal".utf8))
        }
        if !FileManager.default.fileExists(atPath: shmPath) {
            FileManager.default.createFile(atPath: shmPath, contents: Data("shm".utf8))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath))

        // Trigger recovery
        manager.recoverCorruptedDatabase()

        // Database should be re-opened and clean
        let fetched = manager.fetchItems(limit: 10)
        XCTAssertEqual(fetched.count, 0) // New fresh database

        // Can insert new items into the recovered database
        let newItem = ClipboardItem(
            id: UUID(),
            contentType: .text,
            plainText: "Post-recovery clip",
            contentHash: "post_hash"
        )
        manager.insertOrUpdateItem(newItem)

        let postFetched = manager.fetchItems(limit: 10)
        XCTAssertEqual(postFetched.count, 1)
        XCTAssertEqual(postFetched.first?.plainText, "Post-recovery clip")
    }

    func testDatabaseInsertUpdateDeleteLifecycle() {
        let id = UUID()
        let item = ClipboardItem(
            id: id,
            contentType: .text,
            plainText: "Lifecycle item",
            isPinned: false,
            contentHash: "lifecycle_hash"
        )

        // 1. Insert
        dbManager.insertOrUpdateItem(item)
        var fetched = dbManager.findItemByHash("lifecycle_hash")
        XCTAssertNotNil(fetched)
        XCTAssertFalse(fetched!.isPinned)

        // 2. Set pinned
        dbManager.setPinned(id: id, isPinned: true)
        fetched = dbManager.findItemByHash("lifecycle_hash")
        XCTAssertTrue(fetched?.isPinned == true)

        // 3. Update image and thumbnail paths
        dbManager.updateImageAndThumbnailPaths(id: id, imagePath: "images/test.png", thumbPath: "thumbnails/test_thumb.png")
        fetched = dbManager.findItemByHash("lifecycle_hash")
        XCTAssertEqual(fetched?.imageRelativePath, "images/test.png")
        XCTAssertEqual(fetched?.thumbnailRelativePath, "thumbnails/test_thumb.png")

        // 4. Update timestamp
        let futureDate = Date().addingTimeInterval(300)
        dbManager.updateTimestamp(id: id, newTimestamp: futureDate)
        fetched = dbManager.findItemByHash("lifecycle_hash")
        XCTAssertEqual(Int(fetched!.timestamp.timeIntervalSince1970), Int(futureDate.timeIntervalSince1970))

        // 5. Delete item
        let paths = dbManager.deleteItem(id: id)
        XCTAssertEqual(paths.imagePath, "images/test.png")
        XCTAssertEqual(paths.thumbPath, "thumbnails/test_thumb.png")

        let afterDelete = dbManager.findItemByHash("lifecycle_hash")
        XCTAssertNil(afterDelete)
    }

    func testImageRetryCancellation() {
        let monitor = ClipboardMonitor.shared

        // Ensure retry queue starts clean
        monitor.cancelPendingRetries()
        XCTAssertEqual(monitor.pendingRetriesCount, 0)

        // Calling cancel on nonexistent path does not crash
        monitor.cancelPendingRetries(for: "/nonexistent/path.png")
        XCTAssertEqual(monitor.pendingRetriesCount, 0)
    }

    func testClipboardDeduplicationAndTimestampBump() {
        let hash = "dedup_hash_test"
        let firstDate = Date().addingTimeInterval(-100)
        let item1 = ClipboardItem(
            id: UUID(),
            contentType: .text,
            plainText: "Repeated text",
            timestamp: firstDate,
            contentHash: hash
        )
        dbManager.insertOrUpdateItem(item1)

        let initial = dbManager.fetchItems(limit: 5)
        XCTAssertEqual(initial.count, 1)
        XCTAssertEqual(Int(initial.first!.timestamp.timeIntervalSince1970), Int(firstDate.timeIntervalSince1970))

        // Update timestamp for existing item
        let newDate = Date()
        dbManager.updateTimestamp(id: item1.id, newTimestamp: newDate)

        let updated = dbManager.fetchItems(limit: 5)
        XCTAssertEqual(updated.count, 1) // No duplicate row created
        XCTAssertEqual(Int(updated.first!.timestamp.timeIntervalSince1970), Int(newDate.timeIntervalSince1970))
    }

    @MainActor
    func testSelectionPreservationOnNewItems() {
        let store = ClipboardStore(dbManager: dbManager, fileManager: fileManager)

        let item1 = ClipboardItem(id: UUID(), contentType: .text, plainText: "Item 1", timestamp: Date().addingTimeInterval(3), contentHash: "h1")
        let item2 = ClipboardItem(id: UUID(), contentType: .text, plainText: "Item 2", timestamp: Date().addingTimeInterval(2), contentHash: "h2")
        let item3 = ClipboardItem(id: UUID(), contentType: .text, plainText: "Item 3", timestamp: Date().addingTimeInterval(1), contentHash: "h3")

        dbManager.insertOrUpdateItem(item1)
        dbManager.insertOrUpdateItem(item2)
        dbManager.insertOrUpdateItem(item3)

        store.refreshSync()
        XCTAssertEqual(store.items.count, 3)

        // User explicitly selects item 2
        store.selectItem(item2)
        XCTAssertEqual(store.selectedItemId, item2.id)

        // A new item arrives
        let newItem = ClipboardItem(id: UUID(), contentType: .text, plainText: "Item 4", timestamp: Date().addingTimeInterval(4), contentHash: "h4")
        dbManager.insertOrUpdateItem(newItem)

        store.refreshSync()
        XCTAssertEqual(store.items.count, 4)
        // Selection must be preserved!
        XCTAssertEqual(store.selectedItemId, item2.id)
    }

    func testInternalClipboardRestorationMarker() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.test.pasteboard.internal.\(UUID().uuidString)"))
        pasteboard.declareTypes([ClipboardMonitor.internalRestorationType, .string], owner: nil)
        pasteboard.setString("Internal test clip", forType: .string)

        let filter = PrivacyFilter()
        // Must ignore internal restoration pasteboard writes
        let shouldIgnore = filter.shouldIgnore(pasteboard: pasteboard, sourceBundleID: nil)
        XCTAssertTrue(shouldIgnore)
    }

    func testVersionComparisonLogic() {
        XCTAssertTrue(UpdateManager.isVersion("1.0.1", newerThan: "1.0.0"))
        XCTAssertTrue(UpdateManager.isVersion("v1.2.0", newerThan: "1.1.9"))
        XCTAssertTrue(UpdateManager.isVersion("2.0.0", newerThan: "1.99.99"))
        XCTAssertTrue(UpdateManager.isVersion("1.0.1.1", newerThan: "1.0.1"))

        XCTAssertFalse(UpdateManager.isVersion("1.0.0", newerThan: "1.0.0"))
        XCTAssertFalse(UpdateManager.isVersion("1.0", newerThan: "1.0.0"))
        XCTAssertFalse(UpdateManager.isVersion("0.9.9", newerThan: "1.0.0"))
        XCTAssertFalse(UpdateManager.isVersion("v1.0.0", newerThan: "v1.0.1"))
    }

    func testGitHubReleaseJSONDecoding() throws {
        let json = """
        {
            "id": 987654,
            "tag_name": "v1.0.1",
            "name": "WinV Clipboard v1.0.1",
            "body": "Fixed image preview and keyboard navigation",
            "html_url": "https://github.com/anujawitharana/clipbaord-for-mac/releases/tag/v1.0.1",
            "assets": [
                {
                    "name": "WinVClipboard.app.zip",
                    "browser_download_url": "https://github.com/anujawitharana/clipbaord-for-mac/releases/download/v1.0.1/WinVClipboard.app.zip"
                }
            ]
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.id, 987654)
        XCTAssertEqual(release.tagName, "v1.0.1")
        XCTAssertEqual(release.name, "WinV Clipboard v1.0.1")
        XCTAssertEqual(release.body, "Fixed image preview and keyboard navigation")
        XCTAssertEqual(release.assets.count, 1)
        XCTAssertEqual(release.assets.first?.name, "WinVClipboard.app.zip")
        XCTAssertEqual(release.assets.first?.browserDownloadURL, "https://github.com/anujawitharana/clipbaord-for-mac/releases/download/v1.0.1/WinVClipboard.app.zip")
    }

    @MainActor
    func testUpdateManagerStatusAndAutoCheckDefaults() {
        let manager = UpdateManager(currentVersion: "1.0.0")
        XCTAssertEqual(manager.status, .idle)
        XCTAssertEqual(manager.currentVersion, "1.0.0")
        XCTAssertTrue(manager.isAutoCheckEnabled)
    }
}
