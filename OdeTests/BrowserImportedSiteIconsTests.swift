import Foundation
import SQLite3
import XCTest

@testable import Ode

/// The icons another browser kept come over from its own databases, read from
/// a copy while it runs: Chromium's largest bitmap of the page's icon, else
/// the icon of the closest page of its site, and Mozilla's page or root icon.
/// Every database here is a synthetic fixture.
@MainActor
final class BrowserImportedSiteIconsTests: XCTestCase {
    func testChromiumAndMozillaProfilesGiveEachPageItsLargestIconEvenWhileLocked() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("site-icons-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chromium = root.appendingPathComponent("Default", isDirectory: true)
        let mozilla = root.appendingPathComponent("abcd.default-release", isDirectory: true)
        try FileManager.default.createDirectory(at: chromium, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mozilla, withIntermediateDirectories: true)
        let small = SiteIconFixture.png(side: 16)
        let large = SiteIconFixture.png(side: 64)
        let docs = SiteIconFixture.png(side: 32, red: 0.2)
        let mozillaIcon = SiteIconFixture.png(side: 48, red: 0.4)
        let rootIcon = SiteIconFixture.png(side: 32, red: 0.6)

        let favicons = try Self.database(
            at: chromium.appendingPathComponent("Favicons"),
            [
                "CREATE TABLE favicons (id INTEGER PRIMARY KEY, url LONGVARCHAR NOT NULL, icon_type INTEGER DEFAULT 1)",
                """
                CREATE TABLE favicon_bitmaps (id INTEGER PRIMARY KEY, icon_id INTEGER NOT NULL,
                last_updated INTEGER DEFAULT 0, image_data BLOB, width INTEGER DEFAULT 0, height INTEGER DEFAULT 0,
                last_requested INTEGER DEFAULT 0)
                """,
                """
                CREATE TABLE icon_mapping (id INTEGER PRIMARY KEY, page_url LONGVARCHAR NOT NULL, icon_id INTEGER,
                page_url_type INTEGER DEFAULT 0)
                """,
                "INSERT INTO favicons VALUES (1, 'https://mail.example/favicon.ico', 1)",
                "INSERT INTO favicons VALUES (2, 'https://docs.example/document.ico', 1)",
                "INSERT INTO favicon_bitmaps (icon_id, image_data, width, height) VALUES (1, \(Self.hex(small)), 16, 16)",
                "INSERT INTO favicon_bitmaps (icon_id, image_data, width, height) VALUES (1, \(Self.hex(large)), 64, 64)",
                "INSERT INTO favicon_bitmaps (icon_id, image_data, width, height) VALUES (2, \(Self.hex(docs)), 32, 32)",
                "INSERT INTO icon_mapping (page_url, icon_id) VALUES ('https://mail.example/mail/u/0/', 1)",
                "INSERT INTO icon_mapping (page_url, icon_id) VALUES ('https://docs.example/document/d/one', 2)",
            ])
        defer { sqlite3_close(favicons) }
        for statement in ["PRAGMA locking_mode = EXCLUSIVE", "BEGIN EXCLUSIVE"] {
            XCTAssertEqual(sqlite3_exec(favicons, statement, nil, nil, nil), SQLITE_OK, statement)
        }
        let places = try Self.database(
            at: mozilla.appendingPathComponent("favicons.sqlite"),
            [
                """
                CREATE TABLE moz_icons (id INTEGER PRIMARY KEY, icon_url TEXT NOT NULL, fixed_icon_url_hash INTEGER,
                width INTEGER NOT NULL DEFAULT 0, root INTEGER NOT NULL DEFAULT 0, color INTEGER, expire_ms INTEGER,
                flags INTEGER, data BLOB)
                """,
                "CREATE TABLE moz_pages_w_icons (id INTEGER PRIMARY KEY, page_url TEXT NOT NULL, page_url_hash INTEGER)",
                "CREATE TABLE moz_icons_to_pages (page_id INTEGER NOT NULL, icon_id INTEGER NOT NULL, expire_ms INTEGER)",
                "INSERT INTO moz_icons (id, icon_url, width, root, data) VALUES (1, 'https://fox.example/i.png', 48, 0, \(Self.hex(mozillaIcon)))",
                "INSERT INTO moz_icons (id, icon_url, width, root, data) VALUES (2, 'https://root.example/favicon.ico', 32, 1, \(Self.hex(rootIcon)))",
                "INSERT INTO moz_pages_w_icons (id, page_url) VALUES (1, 'https://fox.example/news')",
                "INSERT INTO moz_icons_to_pages (page_id, icon_id) VALUES (1, 1)",
            ])
        sqlite3_close(places)
        let mailTab = Self.tab("https://mail.example/mail/u/0/#inbox")
        let docTab = Self.tab("https://docs.example/document/d/two/edit")
        let foxTab = Self.tab("https://fox.example/news")
        let rootTab = Self.tab("https://root.example/page")
        let unknownTab = Self.tab("https://unknown.example/")
        let spaces = BrowserStore(
            seed: SessionState.Seed(spaces: [
                SpaceState.Seed(name: "Imported", tabs: [mailTab, docTab, foxTab, rootTab, unknownTab])
            ])
        ).snapshot.spaces

        let icons = BrowserImportedSiteIcons.read(for: spaces, in: [chromium.path, mozilla.path])

        XCTAssertEqual(icons["https://mail.example/mail/u/0/#inbox"], large, "The largest bitmap of the page's icon")
        XCTAssertEqual(icons["https://docs.example/document/d/two/edit"], docs, "The closest page of the site")
        XCTAssertEqual(icons["https://fox.example/news"], mozillaIcon)
        XCTAssertEqual(icons["https://root.example/page"], rootIcon)
        XCTAssertNil(icons["https://unknown.example/"])
        sqlite3_exec(favicons, "COMMIT", nil, nil, nil)
    }

    private static func tab(_ address: String) -> TabState.Seed {
        TabState.Seed(title: address, url: URL(string: address), placement: .pinned)
    }

    private static func database(at url: URL, _ statements: [String]) throws -> OpaquePointer? {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        for statement in statements {
            XCTAssertEqual(sqlite3_exec(database, statement, nil, nil, nil), SQLITE_OK, statement)
        }
        return database
    }

    private static func hex(_ data: Data) -> String {
        "x'" + data.map { String(format: "%02x", $0) }.joined() + "'"
    }
}
