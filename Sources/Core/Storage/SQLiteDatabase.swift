import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite \(code): \(message)" }
}

/// A minimal wrapper over the system SQLite (no third-party dependency). Not thread-safe:
/// own it from a single actor.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    /// Opens or creates the database. Pass ":memory:" for an in-memory database.
    public init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let error = SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
            sqlite3_close(handle)
            throw error
        }
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit { sqlite3_close(handle) }

    public func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    /// Runs a statement with bound parameters; returns the rows (empty for non-SELECT).
    @discardableResult
    public func query(_ sql: String, _ parameters: [SQLiteValue] = []) throws -> [SQLiteRow] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }

        for (index, value) in parameters.enumerated() {
            let position = Int32(index + 1)
            let result: Int32 = switch value {
            case .null: sqlite3_bind_null(statement, position)
            case .integer(let v): sqlite3_bind_int64(statement, position, v)
            case .real(let v): sqlite3_bind_double(statement, position, v)
            case .text(let v): sqlite3_bind_text(statement, position, v, -1, SQLITE_TRANSIENT)
            case .blob(let v): v.withUnsafeBytes {
                sqlite3_bind_blob(statement, position, $0.baseAddress, Int32($0.count), SQLITE_TRANSIENT)
            }
            }
            guard result == SQLITE_OK else { throw lastError() }
        }

        var rows: [SQLiteRow] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw lastError() }
            var row = SQLiteRow()
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                row.values[name] = switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: .integer(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: .real(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(statement, column)))
                case SQLITE_BLOB:
                    .blob(Data(bytes: sqlite3_column_blob(statement, column), count: Int(sqlite3_column_bytes(statement, column))))
                default: .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    /// Schema version (`PRAGMA user_version`): how many migrations have been applied.
    public var schemaVersion: Int {
        get throws { try query("PRAGMA user_version").first?.int("user_version") ?? 0 }
    }

    /// Brings the schema up to date: runs the migrations after `schemaVersion`, each in its own
    /// transaction together with the version bump. Only append to the list — never edit or
    /// reorder migrations that may have run already. A database from a newer build is left as is.
    public func migrate(_ migrations: [String]) throws {
        let current = try schemaVersion
        for (index, sql) in migrations.enumerated() where index >= current {
            try transaction {
                try execute(sql)
                try execute("PRAGMA user_version = \(index + 1)")
            }
        }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func lastError() -> SQLiteError {
        SQLiteError(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
    }
}

/// `SQLITE_TRANSIENT` is a C macro Swift cannot import: SQLite copies the bound value.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public init(_ value: String?) { self = value.map(SQLiteValue.text) ?? .null }
    public init(_ value: Data?) { self = value.map(SQLiteValue.blob) ?? .null }
    public init(_ value: Int?) { self = value.map { .integer(Int64($0)) } ?? .null }
}

public struct SQLiteRow: Sendable {
    public var values: [String: SQLiteValue] = [:]

    public func int(_ name: String) -> Int? {
        if case .integer(let v) = values[name] { return Int(v) }
        return nil
    }
    public func int64(_ name: String) -> Int64? {
        if case .integer(let v) = values[name] { return v }
        return nil
    }
    public func double(_ name: String) -> Double? {
        switch values[name] {
        case .real(let v): v
        case .integer(let v): Double(v)
        default: nil
        }
    }
    public func string(_ name: String) -> String? {
        if case .text(let v) = values[name] { return v }
        return nil
    }
    public func data(_ name: String) -> Data? {
        if case .blob(let v) = values[name] { return v }
        return nil
    }
}
