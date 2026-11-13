import Foundation

extension SpaceBoosts {
    // MARK: - Actions - Sites

    /// The Boost kept for `site`, on or off.
    func boost(forSite site: String) -> SiteBoost? {
        sites.first { $0.site == site }
    }

    /// The Boost for the page at `url`, on or off.
    func boost(for url: URL?) -> SiteBoost? {
        BrowserSite.of(url).flatMap(boost(forSite:))
    }

    /// The CSS each site's pages wear, for every Boost that is on and changes
    /// something.
    var stylesheets: [String: String] {
        Dictionary(
            sites.filter(\.isEnabled).map { ($0.site, $0.stylesheet) }.filter { !$0.1.isEmpty },
            uniquingKeysWith: { first, _ in first })
    }
}
