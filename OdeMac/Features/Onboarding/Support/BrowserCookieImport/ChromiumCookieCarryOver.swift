import CommonCrypto
import Foundation

/// How many cookies a carry-over brought, and how many it left behind,
/// because they had expired or their value could not be decrypted.
struct ChromiumCookieCarryOverCounts: Equatable, Sendable {
    let carried: Int
    let expired: Int
    let dropped: Int
}

enum ChromiumCookieCarryOverError: Error, Equatable {
    case targetExists
    case unreadableDatabase
}

/// Brings one Chromium cookie database into another Chromium's profile.
/// The source is copied, never opened in place; each encrypted value is
/// decrypted and re-encrypted in memory one row at a time, so no decrypted
/// value reaches disk. An existing target is never replaced.
enum ChromiumCookieCarryOver {
    // MARK: - Static Variables

    /// Seconds from Chromium's epoch, 1601-01-01, to the Unix epoch.
    private static let chromiumEpochOffset: Int64 = 11_644_473_600
    /// From this database version on, Chromium encrypts a cookie's value
    /// behind the SHA-256 of its host_key and drops a cookie whose prefix
    /// does not match.
    private static let domainHashVersion = 24

    // MARK: - Actions - Carrying

    /// Carries the cookies in `source` to `target`, re-encrypting each value
    /// from `sourceKey` to `targetKey`, and leaving out those expired by
    /// `now`. Works on a copy in a private folder of its own under
    /// `temporaryRoot`, which is removed however it ends. Throws
    /// `targetExists` when a file is at `target`, before or after the work.
    static func carry(
        from source: URL,
        to target: URL,
        sourceKey: Data,
        targetKey: Data,
        now: Date = Date(),
        temporaryRoot: URL = FileManager.default.temporaryDirectory
    ) throws -> ChromiumCookieCarryOverCounts {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: target.path) else {
            throw ChromiumCookieCarryOverError.targetExists
        }
        do {
            let database = try BrowserSQLiteDatabase(
                copying: source, access: .readWrite, temporaryRoot: temporaryRoot)
            let counts = try reencrypt(database, sourceKey: sourceKey, targetKey: targetKey, now: now)
            database.close()

            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: database.url.path)
            guard !fileManager.fileExists(atPath: target.path) else {
                throw ChromiumCookieCarryOverError.targetExists
            }
            try fileManager.moveItem(at: database.url, to: target)
            return counts
        } catch is BrowserSQLiteDatabase.Failure {
            throw ChromiumCookieCarryOverError.unreadableDatabase
        }
    }

    // MARK: - Actions - Database

    /// Rewrites `database` in place: expired cookies and those whose value
    /// cannot be decrypted are deleted, every other v10 value is
    /// re-encrypted, and the file is vacuumed and left without a journal.
    private static func reencrypt(
        _ database: BrowserSQLiteDatabase,
        sourceKey: Data,
        targetKey: Data,
        now: Date
    ) throws -> ChromiumCookieCarryOverCounts {
        try database.execute("BEGIN IMMEDIATE")
        let counts: ChromiumCookieCarryOverCounts
        do {
            let expired = try deleteExpired(in: database, now: now)
            let dropped = try reencryptValues(in: database, sourceKey: sourceKey, targetKey: targetKey)
            let carried = try integer("SELECT count(*) FROM cookies", in: database)
            try database.execute("COMMIT")
            counts = ChromiumCookieCarryOverCounts(carried: carried, expired: expired, dropped: dropped)
        } catch {
            _ = try? database.execute("ROLLBACK")
            throw error
        }
        try database.execute("VACUUM")
        // Only the database file moves to the target, so nothing may stay
        // behind in a write-ahead log.
        try database.execute("PRAGMA journal_mode = DELETE")
        return counts
    }

    /// Deletes the cookies that expire before `now`, and answers how many.
    private static func deleteExpired(in database: BrowserSQLiteDatabase, now: Date) throws -> Int {
        let seconds = Int64(now.timeIntervalSince1970.rounded(.down)) + chromiumEpochOffset
        return try database.execute(
            "DELETE FROM cookies WHERE has_expires = 1 AND expires_utc < ?", [.integer(Int(seconds * 1_000_000))])
    }

    /// Re-encrypts every v10 value from `sourceKey` to `targetKey`, one row
    /// at a time, deleting each row whose value does not decrypt. Answers
    /// how many it deleted.
    private static func reencryptValues(
        in database: BrowserSQLiteDatabase,
        sourceKey: Data,
        targetKey: Data
    ) throws -> Int {
        // The rows are listed before any is rewritten, since a rewritten
        // value still starts with v10 and must not be read again.
        var rowIDs: [Int] = []
        let encryptedRows = "SELECT rowid FROM cookies WHERE substr(encrypted_value, 1, 3) = X'763130'"
        try database.query(encryptedRows, limit: .max) { row in
            rowIDs.append(row.integer(0))
            return true
        }
        let version = try integer("SELECT value FROM meta WHERE key = 'version'", in: database)
        let checksDomainHash = version >= domainHashVersion
        let select = try database.statement("SELECT encrypted_value, host_key FROM cookies WHERE rowid = ?")
        let update = try database.statement("UPDATE cookies SET encrypted_value = ? WHERE rowid = ?")
        let delete = try database.statement("DELETE FROM cookies WHERE rowid = ?")

        var dropped = 0
        for rowID in rowIDs {
            var found: (encrypted: Data?, domainHash: Data?)?
            try select.query([.integer(rowID)], limit: 1) { row in
                found = (row.data(0), checksDomainHash ? sha256(row.text(1) ?? "") : nil)
                return false
            }
            guard let found else { continue }
            if let reencrypted = reencrypted(
                found.encrypted,
                domainHash: found.domainHash,
                sourceKey: sourceKey,
                targetKey: targetKey
            ) {
                try update.execute([.blob(reencrypted), .integer(rowID)])
            } else {
                try delete.execute([.integer(rowID)])
                dropped += 1
            }
        }
        return dropped
    }

    /// `encrypted` under `targetKey`, or nil when `sourceKey` cannot decrypt
    /// it or, given `domainHash`, the decrypted value does not begin with it.
    /// A wrong key passes the padding check about once in 256 values; the
    /// domain hash is what tells those apart. The decrypted bytes are cleared
    /// before this returns.
    private static func reencrypted(
        _ encrypted: Data?,
        domainHash: Data?,
        sourceKey: Data,
        targetKey: Data
    ) -> Data? {
        guard let encrypted, var plaintext = decrypted(encrypted, key: sourceKey) else { return nil }
        defer { plaintext.resetBytes(in: plaintext.startIndex..<plaintext.endIndex) }
        if let domainHash, !plaintext.starts(with: domainHash) { return nil }
        return try? ChromiumPasswordCrypto.encrypt(plaintext, key: targetKey)
    }

    /// The SHA-256 digest of `text`'s UTF-8 bytes.
    static func sha256(_ text: String) -> Data {
        let bytes = Data(text.utf8)
        var digest = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        digest.withUnsafeMutableBytes { digestBytes in
            bytes.withUnsafeBytes { textBytes in
                _ = CC_SHA256(
                    textBytes.baseAddress,
                    CC_LONG(bytes.count),
                    digestBytes.bindMemory(to: UInt8.self).baseAddress
                )
            }
        }
        return digest
    }

    /// The v10 value `encrypted` decrypted with `key`, or nil when it is not
    /// whole AES blocks or its PKCS7 padding does not check out, as with a
    /// value another key encrypted. CommonCrypto's own padding removal
    /// accepts any final block, so the padding is removed here instead.
    private static func decrypted(_ encrypted: Data, key: Data) -> Data? {
        guard encrypted.count > 3,
            encrypted.prefix(3) == Data("v10".utf8),
            (encrypted.count - 3).isMultiple(of: kCCBlockSizeAES128)
        else { return nil }
        let ciphertext = encrypted.dropFirst(3)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: ciphertext.count)
        let outputCount = output.count
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { ciphertextBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            ciphertextBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputCount,
                            &moved
                        )
                    }
                }
            }
        }
        let padding = Int(output.last ?? 0)
        guard status == kCCSuccess,
            moved == outputCount,
            (1...kCCBlockSizeAES128).contains(padding),
            output.suffix(padding).allSatisfy({ Int($0) == padding })
        else {
            output.resetBytes(in: output.startIndex..<output.endIndex)
            return nil
        }
        output.resetBytes(in: (output.endIndex - padding)..<output.endIndex)
        output.removeSubrange((output.endIndex - padding)..<output.endIndex)
        return output
    }

    /// The integer in the first column of `sql`'s first row.
    private static func integer(_ sql: String, in database: BrowserSQLiteDatabase) throws -> Int {
        var value: Int?
        try database.query(sql, limit: 1) { row in
            value = row.integer(0)
            return false
        }
        guard let value else { throw ChromiumCookieCarryOverError.unreadableDatabase }
        return value
    }
}
