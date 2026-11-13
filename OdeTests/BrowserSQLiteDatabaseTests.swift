import Foundation
import SQLite3
import XCTest

@testable import Ode

/// Another browser's database is read from a copy taken while that browser
/// still writes to it: the copy carries the rows only its write-ahead log
/// holds, refuses writes, leaves the original as it was, and goes with the
/// database that read it.
final class BrowserSQLiteDatabaseTests: XCTestCase {
    func testCopyReadsTheWriteAheadLogAndRefusesWrites() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sqlite-copy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let temporaryRoot = folder.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("History")
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(source.path, &writer), SQLITE_OK)
        defer { sqlite3_close(writer) }
        for statement in [
            "PRAGMA journal_mode = WAL",
            "PRAGMA wal_autocheckpoint = 0",
            "CREATE TABLE pages (id INTEGER PRIMARY KEY, address TEXT, icon BLOB)",
            "INSERT INTO pages VALUES (1, 'https://one.example/', x'0102')",
            "INSERT INTO pages VALUES (2, 'https://two.example/', NULL)",
        ] {
            XCTAssertEqual(sqlite3_exec(writer, statement, nil, nil, nil), SQLITE_OK, statement)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path + "-wal"))
        let originalBytes = try Data(contentsOf: source)

        var rows: [String] = []
        var icons: [Data?] = []
        do {
            let database = try BrowserSQLiteDatabase(copying: source, access: .readOnly, temporaryRoot: temporaryRoot)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryRoot.path).count, 1)
            try database.query("SELECT id, address, icon FROM pages WHERE id >= ? ORDER BY id", [.integer(1)]) {
                row in
                rows.append("\(row.integer(0)) \(row.text(1) ?? "")")
                icons.append(row.data(2))
                return true
            }
            XCTAssertThrowsError(try database.execute("DELETE FROM pages"))
        }

        XCTAssertEqual(rows, ["1 https://one.example/", "2 https://two.example/"])
        XCTAssertEqual(icons, [Data([1, 2]), nil])
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryRoot.path), [])
        XCTAssertThrowsError(try BrowserSQLiteDatabase(copying: folder, access: .readOnly)) { error in
            XCTAssertEqual(error as? BrowserSQLiteDatabase.Failure, .unreadableFile)
        }
        XCTAssertThrowsError(
            try BrowserSQLiteDatabase(copying: folder.appendingPathComponent("Missing"), access: .readOnly))
    }
}
