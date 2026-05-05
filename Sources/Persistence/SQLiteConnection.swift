import Foundation
import SQLite3

public enum PersistenceError: Error, Sendable, Equatable, CustomStringConvertible {
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case migrationFailed(String)
    case transactionFailed(String)

    public var description: String {
        switch self {
        case .openFailed(let message):
            "openFailed(\(message))"
        case .prepareFailed(let message):
            "prepareFailed(\(message))"
        case .bindFailed(let message):
            "bindFailed(\(message))"
        case .stepFailed(let message):
            "stepFailed(\(message))"
        case .migrationFailed(let message):
            "migrationFailed(\(message))"
        case .transactionFailed(let message):
            "transactionFailed(\(message))"
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

internal final class SQLiteConnection {
    private var handle: OpaquePointer?
    private var isInTransaction = false

    internal init(path: String) throws {
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(
            path,
            &opened,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard result == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite open error"
            if let opened {
                sqlite3_close(opened)
            }
            throw PersistenceError.openFailed(message)
        }

        handle = opened
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    internal func execute(_ sql: String) throws {
        let statement = try prepare(sql)
        while try statement.step() {}
    }

    internal func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw PersistenceError.prepareFailed(errorMessage)
        }
        return SQLiteStatement(connection: self, statement: statement)
    }

    internal func begin() throws {
        guard !isInTransaction else {
            throw PersistenceError.transactionFailed("transaction already active")
        }
        try execute("BEGIN IMMEDIATE TRANSACTION")
        isInTransaction = true
    }

    internal func commit() throws {
        guard isInTransaction else {
            throw PersistenceError.transactionFailed("no active transaction")
        }
        do {
            try execute("COMMIT")
            isInTransaction = false
        } catch {
            isInTransaction = false
            throw error
        }
    }

    internal func rollback() throws {
        guard isInTransaction else {
            throw PersistenceError.transactionFailed("no active transaction")
        }
        do {
            try execute("ROLLBACK")
            isInTransaction = false
        } catch {
            isInTransaction = false
            throw error
        }
    }

    internal func transaction<T>(_ body: () throws -> T) throws -> T {
        if isInTransaction {
            return try body()
        }

        try begin()

        do {
            let value = try body()
            try commit()
            return value
        } catch {
            do {
                try rollback()
            } catch let rollbackError {
                throw PersistenceError.transactionFailed(rollbackError.localizedDescription)
            }
            throw error
        }
    }

    internal var errorMessage: String {
        guard let handle else {
            return "sqlite connection is closed"
        }
        return String(cString: sqlite3_errmsg(handle))
    }
}

internal final class SQLiteStatement {
    private let connection: SQLiteConnection
    private var statement: OpaquePointer?

    fileprivate init(connection: SQLiteConnection, statement: OpaquePointer) {
        self.connection = connection
        self.statement = statement
    }

    deinit {
        if let statement {
            sqlite3_finalize(statement)
        }
    }

    internal func bind(_ value: String?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw PersistenceError.bindFailed(connection.errorMessage)
        }
    }

    internal func bind(_ value: Int?, at index: Int32) throws {
        if let value {
            try bind(Int64(value), at: index)
        } else {
            try bindNull(at: index)
        }
    }

    internal func bind(_ value: Int64?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_int64(statement, index, value)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw PersistenceError.bindFailed(connection.errorMessage)
        }
    }

    internal func bind(_ value: Double?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_double(statement, index, value)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw PersistenceError.bindFailed(connection.errorMessage)
        }
    }

    internal func bind(_ value: Bool, at index: Int32) throws {
        try bind(value ? 1 : 0, at: index)
    }

    internal func bind(_ value: Data?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = value.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(value.count), sqliteTransient)
            }
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw PersistenceError.bindFailed(connection.errorMessage)
        }
    }

    internal func bindNull(at index: Int32) throws {
        guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
            throw PersistenceError.bindFailed(connection.errorMessage)
        }
    }

    internal func step() throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw PersistenceError.stepFailed(connection.errorMessage)
        }
    }

    internal func string(at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    internal func int(at index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Int(sqlite3_column_int64(statement, index))
    }

    internal func int64(at index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(statement, index)
    }

    internal func double(at index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_double(statement, index)
    }

    internal func bool(at index: Int32) -> Bool {
        sqlite3_column_int64(statement, index) != 0
    }

    internal func data(at index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, index) else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: bytes, count: count)
    }
}
