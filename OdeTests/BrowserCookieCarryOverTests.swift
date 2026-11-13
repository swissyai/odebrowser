import Foundation
import SQLite3
import XCTest

@testable import Ode

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class BrowserCookieCarryOverTests: XCTestCase {
    private let sourceKey = Data(repeating: 0x11, count: 16)
    private let targetKey = Data(repeating: 0x22, count: 16)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// `now` in Chromium's time: microseconds since 1601-01-01.
    private var chromiumNow: Int64 { (1_800_000_000 + 11_644_473_600) * 1_000_000 }
    private let day: Int64 = 86_400 * 1_000_000

    func testEncryptIsTheInverseOfDecrypt() throws {
        let key = try ChromiumPasswordCrypto.key(safeStorageSecret: "test-safe-storage")
        let encrypted = try ChromiumPasswordCrypto.encrypt(Data("hunter2".utf8), key: key)

        XCTAssertEqual(encrypted, Data("v10".utf8) + Data(hex: "13aaf27b4bd1b4ad2dbdea76e9ff6575"))
        XCTAssertEqual(try ChromiumPasswordCrypto.decrypt(encrypted, key: key), Data("hunter2".utf8))
    }

    func testCarryOverReencryptsLiveCookiesAndLeavesTheRestBehind() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let temporaryRoot = folder.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("Arc/Default/Cookies")
        let target = folder.appendingPathComponent("Chromium/Crest-profile/Cookies")
        // At version 24 a value is the SHA-256 of its host_key, then the cookie.
        let domainHash = ChromiumCookieCarryOver.sha256(".example.com")
        let persistentValue = domainHash + Data("persistent-session-token".utf8)
        let sessionValue = domainHash + Data(repeating: 0xAB, count: 48)
        try createCookieDatabase(
            at: source,
            cookies: [
                SampleCookie(
                    name: "persistent",
                    encryptedValue: try ChromiumPasswordCrypto.encrypt(persistentValue, key: sourceKey),
                    hasExpires: true,
                    expiresUTC: chromiumNow + day
                ),
                SampleCookie(
                    name: "session",
                    encryptedValue: try ChromiumPasswordCrypto.encrypt(sessionValue, key: sourceKey),
                    hasExpires: false,
                    expiresUTC: 0
                ),
                SampleCookie(
                    name: "expired",
                    encryptedValue: try ChromiumPasswordCrypto.encrypt(domainHash + Data("old".utf8), key: sourceKey),
                    hasExpires: true,
                    expiresUTC: chromiumNow - day
                ),
                SampleCookie(
                    name: "undecryptable",
                    encryptedValue: Data("v10".utf8) + Data([1, 2, 3, 4, 5, 6, 7]),
                    hasExpires: true,
                    expiresUTC: chromiumNow + day
                ),
                SampleCookie(
                    name: "other-host",
                    encryptedValue: try ChromiumPasswordCrypto.encrypt(
                        ChromiumCookieCarryOver.sha256(".other.example") + Data("token".utf8),
                        key: sourceKey
                    ),
                    hasExpires: true,
                    expiresUTC: chromiumNow + day
                ),
                SampleCookie(
                    name: "other-key",
                    encryptedValue: try ChromiumPasswordCrypto.encrypt(
                        Data("other-profile-token".utf8),
                        key: Data(repeating: 0x33, count: 16)
                    ),
                    hasExpires: true,
                    expiresUTC: chromiumNow + day
                ),
            ]
        )

        let counts = try ChromiumCookieCarryOver.carry(
            from: source,
            to: target,
            sourceKey: sourceKey,
            targetKey: targetKey,
            now: now,
            temporaryRoot: temporaryRoot
        )

        XCTAssertEqual(counts, ChromiumCookieCarryOverCounts(carried: 2, expired: 1, dropped: 3))
        let carried = try encryptedValues(at: target)
        XCTAssertEqual(carried.keys.sorted(), ["persistent", "session"])
        XCTAssertEqual(
            try ChromiumPasswordCrypto.decrypt(try XCTUnwrap(carried["persistent"]), key: targetKey),
            persistentValue
        )
        XCTAssertEqual(
            try ChromiumPasswordCrypto.decrypt(try XCTUnwrap(carried["session"]), key: targetKey),
            sessionValue
        )
        XCTAssertNotEqual(
            try? ChromiumPasswordCrypto.decrypt(try XCTUnwrap(carried["persistent"]), key: sourceKey),
            persistentValue
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryRoot.path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path + "-journal"))
    }

    func testCarryOverLeavesAnExistingTargetUntouched() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let temporaryRoot = folder.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("Arc/Default/Cookies")
        let target = folder.appendingPathComponent("Chromium/Crest-profile/Cookies")
        try createCookieDatabase(
            at: source,
            cookies: [
                SampleCookie(
                    name: "persistent",
                    encryptedValue: try ChromiumPasswordCrypto.encrypt(Data("token".utf8), key: sourceKey),
                    hasExpires: true,
                    expiresUTC: chromiumNow + day
                )
            ]
        )
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existing = Data("the profile's own cookies".utf8)
        try existing.write(to: target)

        XCTAssertThrowsError(
            try ChromiumCookieCarryOver.carry(
                from: source,
                to: target,
                sourceKey: sourceKey,
                targetKey: targetKey,
                now: now,
                temporaryRoot: temporaryRoot
            )
        ) { error in
            XCTAssertEqual(error as? ChromiumCookieCarryOverError, .targetExists)
        }

        XCTAssertEqual(try Data(contentsOf: target), existing)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryRoot.path), [])
    }

    // MARK: - Fixtures

    private struct SampleCookie {
        let name: String
        let encryptedValue: Data
        let hasExpires: Bool
        let expiresUTC: Int64
    }

    private func makeTemporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("crest-cookie-carry-over-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A cookie database as Chromium keeps it at version 24.
    private func createCookieDatabase(at url: URL, cookies: [SampleCookie]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        let handle = try XCTUnwrap(database)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(
            sqlite3_exec(
                handle,
                """
                CREATE TABLE meta (key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR);
                INSERT INTO meta VALUES ('version', '24'), ('last_compatible_version', '24');
                CREATE TABLE cookies (
                    creation_utc INTEGER NOT NULL,
                    host_key TEXT NOT NULL,
                    top_frame_site_key TEXT NOT NULL,
                    name TEXT NOT NULL,
                    value TEXT NOT NULL,
                    encrypted_value BLOB NOT NULL,
                    path TEXT NOT NULL,
                    expires_utc INTEGER NOT NULL,
                    is_secure INTEGER NOT NULL,
                    is_httponly INTEGER NOT NULL,
                    last_access_utc INTEGER NOT NULL,
                    has_expires INTEGER NOT NULL,
                    is_persistent INTEGER NOT NULL,
                    priority INTEGER NOT NULL,
                    samesite INTEGER NOT NULL,
                    source_scheme INTEGER NOT NULL,
                    source_port INTEGER NOT NULL,
                    last_update_utc INTEGER NOT NULL,
                    source_type INTEGER NOT NULL,
                    has_cross_site_ancestor INTEGER NOT NULL
                );
                """,
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                handle,
                """
                INSERT INTO cookies VALUES (
                    ?, '.example.com', '', ?, '', ?, '/', ?, 1, 1, ?, ?, ?, 1, -1, 2, 443, ?, 0, 0
                );
                """,
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        let insert = try XCTUnwrap(statement)
        defer { sqlite3_finalize(insert) }
        for cookie in cookies {
            sqlite3_reset(insert)
            sqlite3_bind_int64(insert, 1, chromiumNow - day)
            sqlite3_bind_text(insert, 2, cookie.name, -1, sqliteTransient)
            _ = cookie.encryptedValue.withUnsafeBytes { bytes in
                sqlite3_bind_blob(insert, 3, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
            }
            sqlite3_bind_int64(insert, 4, cookie.expiresUTC)
            sqlite3_bind_int64(insert, 5, chromiumNow - day)
            sqlite3_bind_int(insert, 6, cookie.hasExpires ? 1 : 0)
            sqlite3_bind_int(insert, 7, cookie.hasExpires ? 1 : 0)
            sqlite3_bind_int64(insert, 8, chromiumNow - day)
            XCTAssertEqual(sqlite3_step(insert), SQLITE_DONE)
        }
    }

    /// The encrypted value of each cookie in the database at `url`, by name.
    private func encryptedValues(at url: URL) throws -> [String: Data] {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let handle = try XCTUnwrap(database)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(handle, "SELECT name, encrypted_value FROM cookies", -1, &statement, nil),
            SQLITE_OK
        )
        let select = try XCTUnwrap(statement)
        defer { sqlite3_finalize(select) }
        var values: [String: Data] = [:]
        while sqlite3_step(select) == SQLITE_ROW {
            let name = String(cString: try XCTUnwrap(sqlite3_column_text(select, 0)))
            let count = Int(sqlite3_column_bytes(select, 1))
            let bytes = try XCTUnwrap(sqlite3_column_blob(select, 1))
            values[name] = Data(bytes: bytes, count: count)
        }
        return values
    }
}

extension Data {
    fileprivate init(hex: String) {
        self.init(
            stride(from: 0, to: hex.count, by: 2).compactMap { offset in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let end = hex.index(start, offsetBy: 2)
                return UInt8(hex[start..<end], radix: 16)
            })
    }
}
