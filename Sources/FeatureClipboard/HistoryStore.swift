import Core
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Clipboard history on disk: `history.sqlite` (system SQLite) plus `images/` with the original
/// images (stored as PNG) and ~400 px thumbnails. An actor: all disk work happens off the main thread.
actor HistoryStore {
    enum AddResult: Equatable {
        case inserted(ClipItem)
        /// The same content was already there; it moved to the top.
        case bumped(ClipItem)

        var item: ClipItem {
            switch self { case .inserted(let item), .bumped(let item): item }
        }
    }

    private let db: SQLiteDatabase
    private let imagesURL: URL

    init(directory: URL) throws {
        imagesURL = directory.appending(path: "images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        db = try SQLiteDatabase(path: directory.appending(path: "history.sqlite").path)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hash TEXT NOT NULL UNIQUE,
                kind TEXT NOT NULL,
                text TEXT,
                search TEXT NOT NULL DEFAULT '',
                rtf BLOB,
                html BLOB,
                image_file TEXT,
                thumb_file TEXT,
                image_w INTEGER,
                image_h INTEGER,
                files TEXT,
                source_id TEXT,
                source_name TEXT,
                created REAL NOT NULL,
                updated REAL NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0,
                size INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS items_order ON items (pinned, updated DESC);
            """)
    }

    // MARK: Adding

    func add(_ content: ClipContent, sourceBundleID: String?, sourceName: String?, date: Date = Date()) throws -> AddResult {
        let hash = content.hash
        if let existing = try db.query("SELECT id FROM items WHERE hash = ?", [.text(hash)]).first?.int64("id") {
            try db.query("UPDATE items SET updated = ?, source_id = ?, source_name = ? WHERE id = ?",
                         [.real(date.timeIntervalSince1970), SQLiteValue(sourceBundleID), SQLiteValue(sourceName), .integer(existing)])
            return .bumped(try item(existing)!)
        }

        var imageFile: String?
        var thumbFile: String?
        var imageSize: CGSize?
        var size = (content.text?.utf8.count ?? 0) + (content.rtf?.count ?? 0) + (content.html?.count ?? 0)
        if let image = content.image {
            let saved = try saveImage(image)
            imageFile = saved.file
            thumbFile = saved.thumbnail
            imageSize = saved.size
            size += saved.bytes
        }

        try db.query("""
            INSERT INTO items (hash, kind, text, search, rtf, html, image_file, thumb_file, image_w, image_h, files,
                               source_id, source_name, created, updated, size)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .text(hash), .text(content.kind.rawValue), SQLiteValue(content.text),
                .text(Self.searchKey(content.text, files: content.fileURLs, source: sourceName)),
                SQLiteValue(content.rtf), SQLiteValue(content.html), SQLiteValue(imageFile), SQLiteValue(thumbFile),
                SQLiteValue(imageSize.map { Int($0.width) }), SQLiteValue(imageSize.map { Int($0.height) }),
                SQLiteValue(content.fileURLs.isEmpty ? nil : content.fileURLs.map(\.path).joined(separator: "\n")),
                SQLiteValue(sourceBundleID), SQLiteValue(sourceName),
                .real(date.timeIntervalSince1970), .real(date.timeIntervalSince1970), .integer(Int64(size)),
            ])
        return .inserted(try item(db.lastInsertRowID)!)
    }

    // MARK: Reading

    /// Characters of text loaded for list rows.
    static let listTextLimit = 2_000

    func item(_ id: Int64) throws -> ClipItem? {
        try db.query("SELECT * FROM items WHERE id = ?", [.integer(id)]).first.map(makeItem)
    }

    /// Newest first, pinned items first. `query` is a case- and diacritic-insensitive substring.
    func items(kind: ClipKind? = nil, query: String = "", pinnedOnly: Bool = false, limit: Int = 1_000) throws -> [ClipItem] {
        var conditions: [String] = []
        var parameters: [SQLiteValue] = []
        if let kind {
            conditions.append("kind = ?")
            parameters.append(.text(kind.rawValue))
        }
        if pinnedOnly { conditions.append("pinned = 1") }
        let needle = Self.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        if !needle.isEmpty {
            conditions.append("search LIKE ? ESCAPE '\\'")
            parameters.append(.text("%" + Self.escapeLike(needle) + "%"))
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        parameters.append(.integer(Int64(limit)))
        // The list needs no RTF/HTML and only the beginning of long texts; `item(_:)` loads everything.
        return try db.query("""
            SELECT id, kind, substr(text, 1, \(Self.listTextLimit)) AS text, image_file, thumb_file, image_w, image_h,
                   files, source_id, source_name, created, updated, pinned, size
            FROM items \(whereClause) ORDER BY pinned DESC, updated DESC LIMIT ?
            """, parameters).map(makeItem)
    }

    func count() throws -> Int {
        try db.query("SELECT count(*) AS c FROM items").first?.int("c") ?? 0
    }

    /// Bytes on disk: the database plus images and thumbnails.
    func diskUsage() -> Int64 {
        let directory = imagesURL.deletingLastPathComponent()
        let files = (FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey])?
            .compactMap { $0 as? URL }) ?? []
        return files.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    // MARK: Changing

    func setPinned(_ id: Int64, _ pinned: Bool) throws {
        try db.query("UPDATE items SET pinned = ? WHERE id = ?", [.integer(pinned ? 1 : 0), .integer(id)])
    }

    func delete(_ id: Int64) throws {
        try deleteRows("SELECT id, image_file, thumb_file FROM items WHERE id = ?", [.integer(id)])
    }

    func clear(keepPinned: Bool) throws {
        try deleteRows("SELECT id, image_file, thumb_file FROM items" + (keepPinned ? " WHERE pinned = 0" : ""), [])
    }

    /// Applies limits; pinned items are never removed. Returns how many items were deleted.
    @discardableResult
    func prune(maxCount: Int, maxAge: TimeInterval?, now: Date = Date()) throws -> Int {
        var removed = try deleteRows(
            "SELECT id, image_file, thumb_file FROM items WHERE pinned = 0 ORDER BY updated DESC LIMIT -1 OFFSET ?",
            [.integer(Int64(maxCount))]
        )
        if let maxAge {
            removed += try deleteRows(
                "SELECT id, image_file, thumb_file FROM items WHERE pinned = 0 AND updated < ?",
                [.real(now.timeIntervalSince1970 - maxAge)]
            )
        }
        return removed
    }

    // MARK: Private

    @discardableResult
    private func deleteRows(_ select: String, _ parameters: [SQLiteValue]) throws -> Int {
        let rows = try db.query(select, parameters)
        guard !rows.isEmpty else { return 0 }
        try db.transaction {
            for row in rows {
                try db.query("DELETE FROM items WHERE id = ?", [.integer(row.int64("id")!)])
            }
        }
        for row in rows {
            for name in [row.string("image_file"), row.string("thumb_file")].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: imagesURL.appending(path: name))
            }
        }
        return rows.count
    }

    private func makeItem(_ row: SQLiteRow) -> ClipItem {
        let width = row.int("image_w")
        let height = row.int("image_h")
        return ClipItem(
            id: row.int64("id")!,
            kind: ClipKind(rawValue: row.string("kind") ?? "") ?? .text,
            text: row.string("text"),
            rtf: row.data("rtf"),
            html: row.data("html"),
            imageURL: row.string("image_file").map { imagesURL.appending(path: $0) },
            thumbnailURL: row.string("thumb_file").map { imagesURL.appending(path: $0) },
            imageSize: width.flatMap { w in height.map { CGSize(width: w, height: $0) } },
            fileURLs: row.string("files")?.split(separator: "\n").map { URL(fileURLWithPath: String($0)) } ?? [],
            sourceBundleID: row.string("source_id"),
            sourceName: row.string("source_name"),
            createdAt: Date(timeIntervalSince1970: row.double("created") ?? 0),
            updatedAt: Date(timeIntervalSince1970: row.double("updated") ?? 0),
            isPinned: row.int("pinned") == 1,
            byteSize: row.int("size") ?? 0
        )
    }

    private struct SavedImage {
        let file: String
        let thumbnail: String?
        let size: CGSize
        let bytes: Int
    }

    /// Stores the image as PNG (screenshots arrive as huge TIFFs) and makes a thumbnail.
    private func saveImage(_ data: Data) throws -> SavedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        let name = UUID().uuidString
        let file = name + ".png"
        try writePNG(image, to: imagesURL.appending(path: file))

        var thumbnail: String?
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            let thumbFile = name + "_thumb.png"
            try? writePNG(thumb, to: imagesURL.appending(path: thumbFile))
            thumbnail = thumbFile
        }
        let bytes = (try? imagesURL.appending(path: file).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? data.count
        return SavedImage(file: file, thumbnail: thumbnail, size: CGSize(width: image.width, height: image.height), bytes: bytes)
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    // MARK: Search helpers

    /// Lowercased, diacritics removed (ё→е), so search ignores case in any script. SQLite's own
    /// LIKE is case-insensitive only for ASCII.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func searchKey(_ text: String?, files: [URL], source: String?) -> String {
        let parts = [String((text ?? "").prefix(20_000))] + files.map(\.path) + [source ?? ""]
        return normalize(parts.joined(separator: "\n"))
    }

    static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
