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
}
