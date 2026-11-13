import Foundation

/// The site icons a browser built on Chromium kept for the pages it showed,
/// read from a snapshot of a profile's `Favicons` database: which icons each
/// page wore (`icon_mapping`) and each icon's images at the sizes the browser
/// drew it (`favicon_bitmaps`). A page that was never mapped takes the icon
/// of the page of its site whose address it shares most of, as its site's
/// other pages wore it.
final class ChromiumFaviconDatabase {
    // MARK: - Static Variables

    static let fileName = "Favicons"
    /// The most mappings of one site a lookup compares.
    private static let maximumSiteMappings = 2_000

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
        var drawn: [Int: Data?] = [:]
        for pageURL in Set(pageURLs) {
            for iconID in iconIDs(for: pageURL) {
                let image = drawn[iconID] ?? largestImage(of: iconID)
                drawn[iconID] = image
                if let image {
                    icons[pageURL] = image
                    break
                }
            }
        }
        return icons
    }

    /// The icons mapped to `pageURL`, else to the closest page of its site.
    private func iconIDs(for pageURL: String) -> [Int] {
        for address in Self.variants(of: pageURL) {
            var mapped: [Int] = []
            try? database.query("SELECT icon_id FROM icon_mapping WHERE page_url = ?", [.text(address)]) { row in
                mapped.append(row.integer(0))
                return true
            }
            if !mapped.isEmpty { return mapped }
        }
        guard let url = URL(string: pageURL) else { return [] }
        for origin in Self.origins(of: url) {
            var best: (shared: Int, iconID: Int)?
            var counts: [Int: Int] = [:]
            let lowest = origin + "/"
            // The first address after every one under `origin/`: "0"
            // follows "/" in every collation SQLite uses for text.
            let highest = origin + "0"
            try? database.query(
                "SELECT page_url, icon_id FROM icon_mapping WHERE page_url >= ? AND page_url < ?",
                [.text(lowest), .text(highest)], limit: Self.maximumSiteMappings
            ) { row in
                guard let mappedURL = row.text(0) else { return true }
                let iconID = row.integer(1)
                counts[iconID, default: 0] += 1
                let shared = Self.sharedPrefixLength(mappedURL, pageURL)
                if best.map({ shared > $0.shared }) ?? true { best = (shared, iconID) }
                return true
            }
            guard let best else { continue }
            let others = counts.keys.filter { $0 != best.iconID }.sorted {
                counts[$0, default: 0] > counts[$1, default: 0]
            }
            return [best.iconID] + others
        }
        return []
    }

    /// The largest image of the icon `iconID` that Ode can draw, ready to
    /// wear.
    private func largestImage(of iconID: Int) -> Data? {
        var image: Data?
        try? database.query(
            "SELECT image_data FROM favicon_bitmaps WHERE icon_id = ? ORDER BY width * height DESC",
            [.integer(iconID)], limit: 8
        ) { row in
            guard let data = row.data(0), let ready = BrowserSiteIconImage(raster: data) else { return true }
            image = ready.data
            return false
        }
        return image
    }

    // MARK: - Actions - Addresses

    /// `pageURL` as given, then without its fragment, then with or without
    /// its trailing slash.
    private static func variants(of pageURL: String) -> [String] {
        let withoutFragment = pageURL.split(separator: "#", maxSplits: 1).first.map(String.init) ?? pageURL
        let toggled =
            withoutFragment.hasSuffix("/") ? String(withoutFragment.dropLast()) : withoutFragment + "/"
        var variants: [String] = []
        for variant in [pageURL, withoutFragment, toggled] where !variants.contains(variant) {
            variants.append(variant)
        }
        return variants
    }

    /// The site's origin as `url` spells it, then with `www.` added or taken
    /// away.
    private static func origins(of url: URL) -> [String] {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = url.host()?.lowercased(), !host.isEmpty
        else { return [] }
        let port = url.port.map { ":\($0)" } ?? ""
        let other = host.hasPrefix("www.") ? String(host.dropFirst(4)) : "www." + host
        return ["\(scheme)://\(host)\(port)", "\(scheme)://\(other)\(port)"]
    }

    private static func sharedPrefixLength(_ first: String, _ second: String) -> Int {
        zip(first.utf8, second.utf8).prefix { $0 == $1 }.count
    }
}
