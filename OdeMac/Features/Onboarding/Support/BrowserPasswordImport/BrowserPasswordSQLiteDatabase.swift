import Foundation

/// A browser's password database, read from a copy taken while the browser
/// runs. The copy is removed when the reader goes away.
final class BrowserPasswordSQLiteDatabase {
    private let database: BrowserSQLiteDatabase

    init(url: URL) throws {
        do {
            database = try BrowserSQLiteDatabase(copying: url, access: .readOnly)
        } catch {
            throw BrowserPasswordImportError.unreadableDatabase
        }
    }

    func encryptedRecords(limit: Int) throws -> [BrowserEncryptedPasswordRecord] {
        guard limit > 0 else { return [] }
        let sql = """
            SELECT origin_url, username_value, password_value
            FROM logins
            WHERE blacklisted_by_user = 0
              AND username_value <> ''
              AND length(password_value) > 3
            LIMIT ?
            """
        var records: [BrowserEncryptedPasswordRecord] = []
        do {
            try database.query(sql, [.integer(min(limit, Int(Int32.max)))], limit: .max) { row in
                if let record = Self.record(row) { records.append(record) }
                return true
            }
        } catch {
            throw BrowserPasswordImportError.unreadableDatabase
        }
        return records
    }

    /// The login in `row` when it is for a secure origin, names a user and
    /// keeps its password under a key Ode reads (v10 or v11).
    private static func record(_ row: BrowserSQLiteDatabase.Row) -> BrowserEncryptedPasswordRecord? {
        guard let urlString = row.text(0),
            let url = URL(string: urlString),
            let origin = CredentialOrigin(url: url),
            origin.isSecure,
            let username = row.text(1),
            let encryptedPassword = row.data(2),
            encryptedPassword.prefix(3) == Data("v10".utf8)
                || encryptedPassword.prefix(3) == Data("v11".utf8)
        else { return nil }
        return BrowserEncryptedPasswordRecord(origin: origin, username: username, encryptedPassword: encryptedPassword)
    }
}
