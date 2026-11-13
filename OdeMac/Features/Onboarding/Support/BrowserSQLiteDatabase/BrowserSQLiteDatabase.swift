import Foundation
import SQLite3

/// Another browser's SQLite database, worked on through a copy of it and of
/// the files SQLite keeps its state in beside it: a running browser holds its
/// own file locked, and the system's copy takes no lock. The copy lives in a
/// private folder of its own, removed when the database goes; the original is
/// never opened.
///
/// A read-only copy refuses writes, keeps its schema untrusted and caps how
/// long a value or a statement may be, how many columns a table may have and
/// that nothing may be attached. A read-write copy keeps its schema untrusted
/// and SQLite's own limits, since `VACUUM` attaches a database of its own.
final class BrowserSQLiteDatabase {
    // MARK: - Static Variables

    /// The largest database a copy is taken of.
    static let maximumByteCount = 512 * 1_024 * 1_024
    /// The longest value a read-only copy holds and a row hands out.
    static let maximumValueByteCount = 16 * 1_024 * 1_024
    /// The longest text a row hands out.
    static let maximumTextByteCount = 1_024 * 1_024
    /// The files SQLite keeps a database's state in, beside the database.
    private static let companionSuffixes = ["-wal", "-journal"]
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: - Types

    enum Access {
        case readOnly
        case readWrite
    }

    enum Failure: Error, Equatable {
        /// No regular file of at most `maximumByteCount` bytes is at the
        /// address.
        case unreadableFile
        /// The database, or a file SQLite keeps beside it, did not copy.
        case uncopyable
        /// SQLite does not open the copy.
        case unopenable
        /// A statement did not prepare, bind or run to its end.
        case statementFailed
    }

    /// A value bound to a statement's next parameter.
    enum Value {
        case integer(Int)
        case text(String)
        case blob(Data)
    }

    /// One row of a query, read by column.
    struct Row {
        fileprivate let statement: OpaquePointer

        func integer(_ column: Int32) -> Int {
            Int(sqlite3_column_int64(statement, column))
        }

        /// The column's text, or nil when it is null or longer than
        /// `maximumTextByteCount`.
        func text(_ column: Int32) -> String? {
            guard let bytes = sqlite3_column_text(statement, column) else { return nil }
            let count = Int(sqlite3_column_bytes(statement, column))
            guard count >= 0, count <= BrowserSQLiteDatabase.maximumTextByteCount else { return nil }
            return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
        }

        /// The column's bytes, or nil when it is empty, null or longer than
        /// `maximumValueByteCount`.
        func data(_ column: Int32) -> Data? {
            let count = Int(sqlite3_column_bytes(statement, column))
            guard count > 0, count <= BrowserSQLiteDatabase.maximumValueByteCount,
                let bytes = sqlite3_column_blob(statement, column)
            else { return nil }
            return Data(bytes: bytes, count: count)
        }
    }

    /// One prepared statement, run as often as its caller needs and reset
    /// after each run.
    final class Statement {
        private let database: BrowserSQLiteDatabase
        private let handle: OpaquePointer

        fileprivate init(_ sql: String, in database: BrowserSQLiteDatabase) throws {
            var handle: OpaquePointer?
            guard let connection = database.handle,
                sqlite3_prepare_v2(connection, sql, -1, &handle, nil) == SQLITE_OK,
                let handle
            else { throw Failure.statementFailed }
            self.database = database
            self.handle = handle
        }

        deinit { sqlite3_finalize(handle) }

        /// Runs the statement with `arguments` bound in order, handing `row`
        /// each row until it answers false or `limit` rows were read.
        func query(_ arguments: [Value] = [], limit: Int = 10_000, row: (Row) throws -> Bool) throws {
            try bind(arguments)
            defer { sqlite3_reset(handle) }
            var count = 0
            while count < limit {
                let result = sqlite3_step(handle)
                if result == SQLITE_DONE { return }
                guard result == SQLITE_ROW else { throw Failure.statementFailed }
                count += 1
                guard try row(Row(statement: handle)) else { return }
            }
        }

        /// Runs the statement with `arguments` bound in order to its end, and
        /// answers how many rows it changed.
        @discardableResult
        func execute(_ arguments: [Value] = []) throws -> Int {
            try bind(arguments)
            defer { sqlite3_reset(handle) }
            while true {
                let result = sqlite3_step(handle)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw Failure.statementFailed }
            }
            return database.handle.map { Int(sqlite3_changes($0)) } ?? 0
        }

        private func bind(_ arguments: [Value]) throws {
            sqlite3_reset(handle)
            sqlite3_clear_bindings(handle)
            for (offset, argument) in arguments.enumerated() {
                let index = Int32(offset + 1)
                let result: Int32
                switch argument {
                case .integer(let value):
                    result = sqlite3_bind_int64(handle, index, Int64(value))
                case .text(let value):
                    result = sqlite3_bind_text(handle, index, value, -1, BrowserSQLiteDatabase.transient)
                case .blob(let value) where value.isEmpty:
                    result = sqlite3_bind_zeroblob(handle, index, 0)
                case .blob(let value):
                    result = value.withUnsafeBytes { bytes in
                        sqlite3_bind_blob(
                            handle, index, bytes.baseAddress, Int32(bytes.count), BrowserSQLiteDatabase.transient)
                    }
                }
                guard result == SQLITE_OK else { throw Failure.statementFailed }
            }
        }
    }

    // MARK: - Variables

    /// The copy this database reads and writes.
    let url: URL
    private let folder: URL
    private var handle: OpaquePointer?

    // MARK: - Initializers

    /// Copies the database at `source`, and each file SQLite keeps beside it,
    /// into a private folder under `temporaryRoot`, and opens the copy.
    init(
        copying source: URL,
        access: Access,
        temporaryRoot: URL = FileManager.default.temporaryDirectory
    ) throws {
        let values = try? source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true, values?.fileSize ?? 0 <= Self.maximumByteCount else {
            throw Failure.unreadableFile
        }
        let fileManager = FileManager.default
        let folder = temporaryRoot.appendingPathComponent("ode-import-\(UUID().uuidString)", isDirectory: true)
        guard
            (try? fileManager.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil
        else { throw Failure.uncopyable }
        let copy = folder.appendingPathComponent(source.lastPathComponent)
        guard Self.copyWithCompanions(source, to: copy) else {
            try? fileManager.removeItem(at: folder)
            throw Failure.uncopyable
        }
        var database: OpaquePointer?
        let flags = (access == .readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(copy.path, &database, flags, nil) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            try? fileManager.removeItem(at: folder)
            throw Failure.unopenable
        }
        self.url = copy
        self.folder = folder
        self.handle = database
        Self.configure(database, for: access)
    }

    deinit {
        close()
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Actions - Statements

    func statement(_ sql: String) throws -> Statement {
        try Statement(sql, in: self)
    }

    /// Runs `sql` with `arguments` bound in order, handing `row` each row
    /// until it answers false or `limit` rows were read.
    func query(_ sql: String, _ arguments: [Value] = [], limit: Int = 10_000, row: (Row) throws -> Bool) throws {
        try statement(sql).query(arguments, limit: limit, row: row)
    }

    /// Runs `sql` with `arguments` bound in order to its end, and answers how
    /// many rows it changed.
    @discardableResult
    func execute(_ sql: String, _ arguments: [Value] = []) throws -> Int {
        try statement(sql).execute(arguments)
    }

    /// Closes the copy, leaving it at `url` until the database goes. A
    /// statement still held keeps the connection open until it goes too.
    func close() {
        guard let handle else { return }
        sqlite3_close_v2(handle)
        self.handle = nil
    }

    // MARK: - Actions - Opening

    private static func configure(_ database: OpaquePointer, for access: Access) {
        sqlite3_busy_timeout(database, 1_000)
        sqlite3_exec(database, "PRAGMA trusted_schema = OFF", nil, nil, nil)
        guard access == .readOnly else { return }
        sqlite3_exec(database, "PRAGMA query_only = ON", nil, nil, nil)
        sqlite3_limit(database, SQLITE_LIMIT_LENGTH, Int32(maximumValueByteCount))
        sqlite3_limit(database, SQLITE_LIMIT_SQL_LENGTH, 64 * 1_024)
        sqlite3_limit(database, SQLITE_LIMIT_COLUMN, 64)
        sqlite3_limit(database, SQLITE_LIMIT_ATTACHED, 0)
    }

    /// Copies `source` to `target`, then each companion `source` has beside
    /// it to the same place beside `target`; false when any of them fails.
    private static func copyWithCompanions(_ source: URL, to target: URL) -> Bool {
        guard copyUnlocked(source.path, to: target.path) else { return false }
        for suffix in companionSuffixes where FileManager.default.fileExists(atPath: source.path + suffix) {
            guard copyUnlocked(source.path + suffix, to: target.path + suffix) else { return false }
        }
        return true
    }

    /// Copies `source`'s data to `target` with the system's copy, which takes
    /// no lock where Foundation's would wait on the browser's.
    private static func copyUnlocked(_ source: String, to target: String) -> Bool {
        copyfile(source, target, nil, copyfile_flags_t(COPYFILE_DATA)) == 0
    }
}
