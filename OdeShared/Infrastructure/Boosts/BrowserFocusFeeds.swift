import Foundation

/// The feeds and recommendations Focus hides, site by site, as each site's
/// pages draw them. They join a page's Boost CSS while Focus is on and leave
/// the Space's own Boosts untouched. Selectors follow the published
/// open-source feed blockers; a site that changes its markup shows again.
struct BrowserFocusFeeds: Sendable {
    // MARK: - Static Variables

    /// YouTube's home feed, the recommendations beside and after a video, and
    /// Shorts.
    static let youTube = BrowserFocusFeeds(
        sites: ["youtube.com", "m.youtube.com"],
        hiddenSelectors: [
            "ytd-browse[page-subtype=\"home\"]", "#related", "ytd-watch-next-secondary-results-renderer",
            ".html5-endscreen", ".ytp-ce-element", "ytd-reel-shelf-renderer", "ytd-rich-shelf-renderer[is-shorts]",
            "ytd-guide-entry-renderer:has(a[title=\"Shorts\"])",
            "ytd-mini-guide-entry-renderer:has(a[title=\"Shorts\"])",
            "yt-tab-shape[tab-title=\"Shorts\"]",
        ])
    /// Reddit's feeds of posts and its trending carousel.
    static let reddit = BrowserFocusFeeds(
        sites: ["reddit.com"], hiddenSelectors: ["shreddit-feed", "shreddit-gallery-carousel", "recent-posts"])
    /// X's trends and news beside the timeline.
    static let x = BrowserFocusFeeds(
        sites: ["x.com", "twitter.com"],
        hiddenSelectors: [
            "div[aria-label=\"Timeline: Trending now\"]", "section:has(div[aria-label=\"Timeline: Trending now\"])",
            "div:has(> div[data-testid=\"news_sidebar\"])",
        ])
    /// Instagram's suggested accounts and the way into Reels.
    static let instagram = BrowserFocusFeeds(
        sites: ["instagram.com"],
        hiddenSelectors: ["div:has(> div > a[href=\"/explore/people/\"])", "a[href=\"/reels/\"]"])

    static let all = [youTube, reddit, x, instagram]

    /// The CSS each site's pages wear while Focus hides feeds.
    static let stylesheets: [String: String] = Dictionary(
        uniqueKeysWithValues: all.flatMap { feeds in feeds.sites.map { ($0, feeds.stylesheet) } })

    // MARK: - Variables

    /// The sites, as Boosts spell them, whose pages draw these feeds.
    let sites: [String]
    let hiddenSelectors: [String]

    /// A rule that hides each feed.
    var stylesheet: String {
        hiddenSelectors.map { "\($0) { display: none !important; }" }.joined(separator: "\n")
    }

    // MARK: - Actions - Lookup

    /// The CSS each site's pages wear: Focus's while it hides feeds, else none.
    static func stylesheets(hidingFeeds: Bool) -> [String: String] {
        hidingFeeds ? stylesheets : [:]
    }
}
