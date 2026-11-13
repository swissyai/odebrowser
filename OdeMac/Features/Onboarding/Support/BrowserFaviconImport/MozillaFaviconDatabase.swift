import Foundation

/// The site icons a Mozilla browser, Firefox or Zen, kept for the pages it
/// showed, read from a snapshot of a profile's `favicons.sqlite`: the icons
/// each page wore (`moz_icons_to_pages`), else the root icon of its site, the
/// `/favicon.ico` it served. An SVG icon, which Mozilla keeps as its source,
/// is left for the lookup that draws it.
final class MozillaFaviconDatabase {
    // MARK: - Static Variables

    static let fileName = "favicons.sqlite"

    // MARK: - Variables

    private let database: BrowserSQLiteDatabase

    // MARK: - Initializers

    /// The icons the profile in `profileFolder` keeps, or nil when it keeps
    /// none Ode can read.
    init?(profileFolder: URL) {
        guard
            let database = try? BrowserSQLiteDatabase(
                copying: profileFolder.appendingPathComponent(Self.fileName), access: .readOnly)
        else { return nil }
        self.database = database
    }

    // MARK: - Actions - Reading

    /// The icon each of `pageURLs` wore, ready for a tab to wear, by address
    /// as given; a page with no icon Ode can draw is left out.
    func icons(for pageURLs: [String]) -> [String: Data] {
        var icons: [String: Data] = [:]
        for pageURL in Set(pageURLs) {
            if let icon = pageIcon(pageURL) ?? rootIcon(pageURL) { icons[pageURL] = icon }
        }
        return icons
    }

    private func pageIcon(_ pageURL: String) -> Data? {
        largestImage(
            """
            SELECT moz_icons.data FROM moz_pages_w_icons
            JOIN moz_icons_to_pages ON moz_icons_to_pages.page_id = moz_pages_w_icons.id
            JOIN moz_icons ON moz_icons.id = moz_icons_to_pages.icon_id
            WHERE moz_pages_w_icons.page_url = ? ORDER BY moz_icons.width DESC
            """, pageURL)
    }

    private func rootIcon(_ pageURL: String) -> Data? {
        guard let url = URL(string: pageURL), let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme), let host = url.host()?.lowercased()
        else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return largestImage(
            "SELECT data FROM moz_icons WHERE root = 1 AND icon_url = ? ORDER BY width DESC",
            "\(scheme)://\(host)\(port)/favicon.ico")
    }

    /// The first image `sql` finds for `argument` that Ode can draw, ready to
    /// wear.
    private func largestImage(_ sql: String, _ argument: String) -> Data? {
        var image: Data?
        try? database.query(sql, [.text(argument)], limit: 8) { row in
            guard let data = row.data(0), let ready = BrowserSiteIconImage(raster: data) else { return true }
            image = ready.data
            return false
        }
        return image
    }
}
