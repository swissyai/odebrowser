import Foundation

/// What a site calls one of its icons, which decides how well the icon suits
/// a tab: the icon it gives browsers, one its web app manifest lists, its home
/// screen icon, the `/favicon.ico` any site may serve, or the one-color
/// silhouette Safari draws for pinned tabs.
struct BrowserSiteIconRelation: Hashable, Sendable {
    // MARK: - Static Variables

    static let icon = BrowserSiteIconRelation(name: "icon", linkTokens: ["icon"], preference: 4)
    static let manifest = BrowserSiteIconRelation(name: "manifest", linkTokens: [], preference: 3)
    static let touchIcon = BrowserSiteIconRelation(
        name: "apple-touch-icon", linkTokens: ["apple-touch-icon", "apple-touch-icon-precomposed"], preference: 2)
    static let defaultIcon = BrowserSiteIconRelation(name: "favicon.ico", linkTokens: [], preference: 1)
    static let maskIcon = BrowserSiteIconRelation(name: "mask-icon", linkTokens: ["mask-icon"], preference: 0)
    /// In the order a `<link>` is matched: a home screen or silhouette token
    /// names that kind even beside a plain `icon` token.
    static let all = [touchIcon, maskIcon, icon, manifest, defaultIcon]

    // MARK: - Variables

    /// How the kind is spelled in reports.
    let name: String
    /// The `rel` tokens of a `<link>` that names an icon of this kind.
    let linkTokens: Set<String>
    /// How strongly this kind is chosen over another of the same size.
    let preference: Int

    // MARK: - Actions - Reading

    /// The kind of icon a `<link>` whose `rel` holds `tokens` names, or nil
    /// when it names none.
    static func linked(by tokens: Set<String>) -> BrowserSiteIconRelation? {
        all.first { !$0.linkTokens.isDisjoint(with: tokens) }
    }
}
