import Foundation

/// The site a page belongs to, as Boosts, Focus limits, tab previews,
/// remembered page backgrounds and blocked-load counts name it: its host in
/// lowercase, without a final dot, and without a leading "www." when a domain
/// remains after it. Scheme, port, user, path and query play no part, so a
/// caller that cares about the scheme checks it itself.
///
/// The core spells a Boost's site by this rule too (`SiteBoost.SiteOf`), and
/// also refuses a site holding characters no host has. Page scripts use
/// `javaScript`, which names the same site for every host.
/// A site is not an origin: site permissions and agent grants key on the
/// scheme, host and port and do not use this rule.
enum BrowserSite {
    private static let worldWideWebPrefix = "www."

    /// The site of the page at `url`, or nil for an address without a host,
    /// such as a file or the Start Page.
    static func of(_ url: URL?) -> String? {
        of(host: url?.host(percentEncoded: false))
    }

    /// The site a page whose host is `host` belongs to, or nil when no host
    /// remains.
    static func of(host: String?) -> String? {
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        var site = host.hasSuffix(".") ? String(host.dropLast()) : host
        if site.hasPrefix(worldWideWebPrefix), site.dropFirst(worldWideWebPrefix.count).contains(".") {
            site = String(site.dropFirst(worldWideWebPrefix.count))
        }
        return site.isEmpty ? nil : site
    }

    /// The same rule as a JavaScript arrow function from a host to its site,
    /// for page scripts that read `location.hostname`. It answers an empty
    /// string where `of(host:)` answers nil.
    static let javaScript = #"""
        (host) => {
          let site = String(host || "").toLowerCase().replace(/\.$/, "");
          if (site.startsWith("www.") && site.slice(4).includes(".")) site = site.slice(4);
          return site;
        }
        """#
}
