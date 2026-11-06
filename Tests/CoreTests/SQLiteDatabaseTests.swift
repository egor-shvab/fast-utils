import Foundation
import Testing
@testable import Core

struct SQLiteDatabaseTests {
    @Test func roundTripsAllValueTypes() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute("CREATE TABLE t (i INTEGER, r REAL, s TEXT, b BLOB, n TEXT)")
        try db.query("INSERT INTO t VALUES (?, ?, ?, ?, ?)",
                     [.integer(42), .real(1.5), .text("Привет"), .blob(Data([1, 2, 3])), .null])
        let row = try #require(try db.query("SELECT * FROM t").first)
        #expect(row.int("i") == 42)
        #expect(row.double("r") == 1.5)
        #expect(row.string("s") == "Привет")
        #expect(row.data("b") == Data([1, 2, 3]))
        #expect(row.string("n") == nil)
    }

    @Test func failedTransactionRollsBack() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute("CREATE TABLE t (x INTEGER UNIQUE)")
        #expect(throws: SQLiteError.self) {
            try db.transaction {
                try db.query("INSERT INTO t VALUES (1)")
                try db.query("INSERT INTO t VALUES (1)")
            }
        }
        #expect(try db.query("SELECT count(*) AS c FROM t").first?.int("c") == 0)
    }

    /// Storage prototype: substring search over a lowercased column on 5 000 rows.
    @Test func substringSearchOn5000RowsIsFast() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, search TEXT, updated REAL)")
        let words = ["договор", "invoice", "пароль", "meeting", "отчёт", "скриншот", "github", "письмо"]
        try db.transaction {
            for i in 0..<5_000 {
                let text = (0..<30).map { words[($0 * 7 + i) % words.count] }.joined(separator: " ") + " #\(i)"
                try db.query("INSERT INTO items (search, updated) VALUES (?, ?)", [.text(text.lowercased()), .real(Double(i))])
            }
        }
        let start = ContinuousClock.now
        let rows = try db.query(
            "SELECT id FROM items WHERE search LIKE ? ESCAPE '\\' ORDER BY updated DESC LIMIT 200",
            [.text("%отчёт%")]
        )
        let elapsed = ContinuousClock.now - start
        #expect(rows.count == 200)
        #expect(elapsed < .milliseconds(50), "search took \(elapsed)")
    }

    @Test func migrationsRunOnceAndInOrder() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        #expect(try db.schemaVersion == 0)
        let v1 = ["CREATE TABLE t (a INTEGER)"]
        try db.migrate(v1)
        try db.migrate(v1)  // already applied: no "table t already exists"
        #expect(try db.schemaVersion == 1)

        try db.migrate(v1 + ["ALTER TABLE t ADD COLUMN b TEXT"])
        #expect(try db.schemaVersion == 2)
        try db.query("INSERT INTO t (a, b) VALUES (1, 'x')")

        // A failing migration leaves the version where it was.
        #expect(throws: SQLiteError.self) { try db.migrate(v1 + ["ALTER TABLE t ADD COLUMN b TEXT", "nonsense"]) }
        #expect(try db.schemaVersion == 2)
    }
}
