import Foundation
import SQLite3

public final class DatabaseManager: @unchecked Sendable {
    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.winvclipboard.databasemanager", qos: .userInitiated)

    public init(databasePath: String) {
        self.dbPath = databasePath
        queue.sync {
            self.openDatabase()
            self.setupSchema()
        }
    }

    deinit {
        queue.sync {
            if let db = db {
                sqlite3_close_v2(db)
            }
        }
    }

    private func openDatabase() {
        let parentDir = (dbPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        let openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(dbPath, &db, openFlags, nil) != SQLITE_OK {
            // Attempt to recover if database is corrupt
            sqlite3_close_v2(db)
            db = nil
            let backupPath = dbPath + ".corrupt.\(Date().timeIntervalSince1970)"
            try? FileManager.default.moveItem(atPath: dbPath, toPath: backupPath)
            _ = sqlite3_open_v2(dbPath, &db, openFlags, nil)
        }

        // Configure WAL mode & synchronous normal for speed and safety
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
    }

    private func setupSchema() {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            content_type TEXT NOT NULL,
            plain_text TEXT,
            rich_content TEXT,
            image_rel_path TEXT,
            thumbnail_rel_path TEXT,
            timestamp REAL NOT NULL,
            source_app_name TEXT,
            source_app_bundle_id TEXT,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            content_hash TEXT NOT NULL,
            char_count INTEGER DEFAULT 0
        );

        CREATE INDEX IF NOT EXISTS idx_timestamp ON clipboard_items(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_hash ON clipboard_items(content_hash);
        CREATE INDEX IF NOT EXISTS idx_pinned ON clipboard_items(is_pinned);
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createTableSQL, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                NSLog("Failed to create schema: %s", errMsg)
                sqlite3_free(errMsg)
            }
        }
    }

    public func executeTransaction<T>(_ block: () throws -> T) throws -> T {
        return try queue.sync {
            guard let db = db else {
                throw NSError(domain: "DatabaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database not opened"])
            }
            sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil)
            do {
                let result = try block()
                sqlite3_exec(db, "COMMIT;", nil, nil, nil)
                return result
            } catch {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw error
            }
        }
    }

    public func insertOrUpdateItem(_ item: ClipboardItem) {
        queue.sync {
            guard let db = db else { return }

            let sql = """
            INSERT INTO clipboard_items (
                id, content_type, plain_text, rich_content, image_rel_path,
                thumbnail_rel_path, timestamp, source_app_name, source_app_bundle_id,
                is_pinned, content_hash, char_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                content_type = excluded.content_type,
                plain_text = excluded.plain_text,
                rich_content = excluded.rich_content,
                image_rel_path = excluded.image_rel_path,
                thumbnail_rel_path = excluded.thumbnail_rel_path,
                timestamp = excluded.timestamp,
                source_app_name = excluded.source_app_name,
                source_app_bundle_id = excluded.source_app_bundle_id,
                is_pinned = excluded.is_pinned,
                content_hash = excluded.content_hash,
                char_count = excluded.char_count;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (item.id.uuidString as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (item.contentType.rawValue as NSString).utf8String, -1, nil)

                if let text = item.plainText {
                    sqlite3_bind_text(stmt, 3, (text as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 3)
                }

                if let rich = item.richContent {
                    sqlite3_bind_text(stmt, 4, (rich as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 4)
                }

                if let img = item.imageRelativePath {
                    sqlite3_bind_text(stmt, 5, (img as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 5)
                }

                if let thumb = item.thumbnailRelativePath {
                    sqlite3_bind_text(stmt, 6, (thumb as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }

                sqlite3_bind_double(stmt, 7, item.timestamp.timeIntervalSince1970)

                if let appName = item.sourceAppName {
                    sqlite3_bind_text(stmt, 8, (appName as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 8)
                }

                if let bundleId = item.sourceAppBundleId {
                    sqlite3_bind_text(stmt, 9, (bundleId as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 9)
                }

                sqlite3_bind_int(stmt, 10, item.isPinned ? 1 : 0)
                sqlite3_bind_text(stmt, 11, (item.contentHash as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 12, Int32(item.charCount))

                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func fetchItems(searchQuery: String? = nil, limit: Int = 100) -> [ClipboardItem] {
        return queue.sync {
            guard let db = db else { return [] }

            var sql = "SELECT id, content_type, plain_text, rich_content, image_rel_path, thumbnail_rel_path, timestamp, source_app_name, source_app_bundle_id, is_pinned, content_hash, char_count FROM clipboard_items "
            var binds: [String] = []

            if let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
                sql += "WHERE plain_text LIKE ? OR source_app_name LIKE ? "
                binds.append("%\(query)%")
                binds.append("%\(query)%")
            }

            // Pinned items stay clearly sorted by timestamp, or grouped if desired; standard Windows order is pinned & unpinned in reverse chron, with pinned badge
            sql += "ORDER BY is_pinned DESC, timestamp DESC LIMIT ?"

            var stmt: OpaquePointer?
            var items: [ClipboardItem] = []

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                var bindIndex: Int32 = 1
                for bind in binds {
                    sqlite3_bind_text(stmt, bindIndex, (bind as NSString).utf8String, -1, nil)
                    bindIndex += 1
                }
                sqlite3_bind_int(stmt, bindIndex, Int32(limit))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let idStr = sqlite3_column_text(stmt, 0),
                          let typeStr = sqlite3_column_text(stmt, 1),
                          let hashStr = sqlite3_column_text(stmt, 10) else { continue }

                    let id = UUID(uuidString: String(cString: idStr)) ?? UUID()
                    let contentType = ContentType(rawValue: String(cString: typeStr)) ?? .text
                    let contentHash = String(cString: hashStr)

                    var plainText: String?
                    if let text = sqlite3_column_text(stmt, 2) {
                        plainText = String(cString: text)
                    }

                    var richContent: String?
                    if let rich = sqlite3_column_text(stmt, 3) {
                        richContent = String(cString: rich)
                    }

                    var imgRelPath: String?
                    if let img = sqlite3_column_text(stmt, 4) {
                        imgRelPath = String(cString: img)
                    }

                    var thumbRelPath: String?
                    if let thumb = sqlite3_column_text(stmt, 5) {
                        thumbRelPath = String(cString: thumb)
                    }

                    let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))

                    var appName: String?
                    if let app = sqlite3_column_text(stmt, 7) {
                        appName = String(cString: app)
                    }

                    var bundleId: String?
                    if let bundle = sqlite3_column_text(stmt, 8) {
                        bundleId = String(cString: bundle)
                    }

                    let isPinned = sqlite3_column_int(stmt, 9) == 1
                    let charCount = Int(sqlite3_column_int(stmt, 11))

                    let item = ClipboardItem(
                        id: id,
                        contentType: contentType,
                        plainText: plainText,
                        richContent: richContent,
                        imageRelativePath: imgRelPath,
                        thumbnailRelativePath: thumbRelPath,
                        timestamp: timestamp,
                        sourceAppName: appName,
                        sourceAppBundleId: bundleId,
                        isPinned: isPinned,
                        contentHash: contentHash,
                        charCount: charCount
                    )
                    items.append(item)
                }
            }
            sqlite3_finalize(stmt)
            return items
        }
    }

    public func findItemByHash(_ hash: String) -> ClipboardItem? {
        return queue.sync {
            guard let db = db else { return nil }
            let sql = "SELECT id, content_type, plain_text, rich_content, image_rel_path, thumbnail_rel_path, timestamp, source_app_name, source_app_bundle_id, is_pinned, content_hash, char_count FROM clipboard_items WHERE content_hash = ? LIMIT 1;"
            var stmt: OpaquePointer?
            var item: ClipboardItem?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (hash as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    if let idStr = sqlite3_column_text(stmt, 0),
                       let typeStr = sqlite3_column_text(stmt, 1),
                       let hashStr = sqlite3_column_text(stmt, 10) {
                        let id = UUID(uuidString: String(cString: idStr)) ?? UUID()
                        let contentType = ContentType(rawValue: String(cString: typeStr)) ?? .text
                        let contentHash = String(cString: hashStr)

                        var plainText: String?
                        if let text = sqlite3_column_text(stmt, 2) { plainText = String(cString: text) }

                        var richContent: String?
                        if let rich = sqlite3_column_text(stmt, 3) { richContent = String(cString: rich) }

                        var imgRelPath: String?
                        if let img = sqlite3_column_text(stmt, 4) { imgRelPath = String(cString: img) }

                        var thumbRelPath: String?
                        if let thumb = sqlite3_column_text(stmt, 5) { thumbRelPath = String(cString: thumb) }

                        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))

                        var appName: String?
                        if let app = sqlite3_column_text(stmt, 7) { appName = String(cString: app) }

                        var bundleId: String?
                        if let bundle = sqlite3_column_text(stmt, 8) { bundleId = String(cString: bundle) }

                        let isPinned = sqlite3_column_int(stmt, 9) == 1
                        let charCount = Int(sqlite3_column_int(stmt, 11))

                        item = ClipboardItem(
                            id: id,
                            contentType: contentType,
                            plainText: plainText,
                            richContent: richContent,
                            imageRelativePath: imgRelPath,
                            thumbnailRelativePath: thumbRelPath,
                            timestamp: timestamp,
                            sourceAppName: appName,
                            sourceAppBundleId: bundleId,
                            isPinned: isPinned,
                            contentHash: contentHash,
                            charCount: charCount
                        )
                    }
                }
            }
            sqlite3_finalize(stmt)
            return item
        }
    }

    public func setPinned(id: UUID, isPinned: Bool) {
        queue.sync {
            guard let db = db else { return }
            let sql = "UPDATE clipboard_items SET is_pinned = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, isPinned ? 1 : 0)
                sqlite3_bind_text(stmt, 2, (id.uuidString as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func updateTimestamp(id: UUID, newTimestamp: Date) {
        queue.sync {
            guard let db = db else { return }
            let sql = "UPDATE clipboard_items SET timestamp = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, newTimestamp.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 2, (id.uuidString as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func deleteItem(id: UUID) -> (imagePath: String?, thumbPath: String?) {
        return queue.sync {
            guard let db = db else { return (nil, nil) }

            // Find image paths before deleting
            var imgRelPath: String?
            var thumbRelPath: String?

            let selectSQL = "SELECT image_rel_path, thumbnail_rel_path FROM clipboard_items WHERE id = ?;"
            var selectStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(selectStmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
                if sqlite3_step(selectStmt) == SQLITE_ROW {
                    if let img = sqlite3_column_text(selectStmt, 0) { imgRelPath = String(cString: img) }
                    if let thumb = sqlite3_column_text(selectStmt, 1) { thumbRelPath = String(cString: thumb) }
                }
            }
            sqlite3_finalize(selectStmt)

            let deleteSQL = "DELETE FROM clipboard_items WHERE id = ?;"
            var deleteStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(deleteStmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
                sqlite3_step(deleteStmt)
            }
            sqlite3_finalize(deleteStmt)

            return (imgRelPath, thumbRelPath)
        }
    }

    public func clearAllUnpinned() -> [(imagePath: String?, thumbPath: String?)] {
        return queue.sync {
            guard let db = db else { return [] }

            var pathsToDelete: [(imagePath: String?, thumbPath: String?)] = []

            let selectSQL = "SELECT image_rel_path, thumbnail_rel_path FROM clipboard_items WHERE is_pinned = 0;"
            var selectStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
                while sqlite3_step(selectStmt) == SQLITE_ROW {
                    var img: String?
                    var thumb: String?
                    if let cImg = sqlite3_column_text(selectStmt, 0) { img = String(cString: cImg) }
                    if let cThumb = sqlite3_column_text(selectStmt, 1) { thumb = String(cString: cThumb) }
                    pathsToDelete.append((img, thumb))
                }
            }
            sqlite3_finalize(selectStmt)

            let deleteSQL = "DELETE FROM clipboard_items WHERE is_pinned = 0;"
            sqlite3_exec(db, deleteSQL, nil, nil, nil)

            return pathsToDelete
        }
    }

    public func pruneUnpinned(keepMax: Int) -> [(imagePath: String?, thumbPath: String?)] {
        return queue.sync {
            guard let db = db else { return [] }

            // Find IDs to prune: unpinned items beyond keepMax ordered by timestamp desc
            let selectSQL = """
            SELECT id, image_rel_path, thumbnail_rel_path FROM clipboard_items
            WHERE is_pinned = 0
            ORDER BY timestamp DESC
            LIMIT -1 OFFSET ?;
            """

            var pathsToDelete: [(imagePath: String?, thumbPath: String?)] = []
            var idsToDelete: [String] = []

            var selectStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(selectStmt, 1, Int32(keepMax))
                while sqlite3_step(selectStmt) == SQLITE_ROW {
                    if let idStr = sqlite3_column_text(selectStmt, 0) {
                        idsToDelete.append(String(cString: idStr))
                    }
                    var img: String?
                    var thumb: String?
                    if let cImg = sqlite3_column_text(selectStmt, 1) { img = String(cString: cImg) }
                    if let cThumb = sqlite3_column_text(selectStmt, 2) { thumb = String(cString: cThumb) }
                    pathsToDelete.append((img, thumb))
                }
            }
            sqlite3_finalize(selectStmt)

            if !idsToDelete.isEmpty {
                sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil)
                for id in idsToDelete {
                    let delSQL = "DELETE FROM clipboard_items WHERE id = ?;"
                    var delStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, delSQL, -1, &delStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(delStmt, 1, (id as NSString).utf8String, -1, nil)
                        sqlite3_step(delStmt)
                    }
                    sqlite3_finalize(delStmt)
                }
                sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            }

            return pathsToDelete
        }
    }

    public func purgeUnpinnedOlderThan(cutoffTimestamp: TimeInterval) -> [(imagePath: String?, thumbPath: String?)] {
        return queue.sync {
            guard let db = db else { return [] }

            let selectSQL = "SELECT image_rel_path, thumbnail_rel_path FROM clipboard_items WHERE is_pinned = 0 AND timestamp < ?;"
            var pathsToDelete: [(imagePath: String?, thumbPath: String?)] = []

            var selectStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(selectStmt, 1, cutoffTimestamp)
                while sqlite3_step(selectStmt) == SQLITE_ROW {
                    var img: String?
                    var thumb: String?
                    if let cImg = sqlite3_column_text(selectStmt, 0) { img = String(cString: cImg) }
                    if let cThumb = sqlite3_column_text(selectStmt, 1) { thumb = String(cString: cThumb) }
                    pathsToDelete.append((img, thumb))
                }
            }
            sqlite3_finalize(selectStmt)

            let deleteSQL = "DELETE FROM clipboard_items WHERE is_pinned = 0 AND timestamp < ?;"
            var delStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSQL, -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(delStmt, 1, cutoffTimestamp)
                sqlite3_step(delStmt)
            }
            sqlite3_finalize(delStmt)

            return pathsToDelete
        }
    }
}
