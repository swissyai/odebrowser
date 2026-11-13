import Foundation
import Observation

/// What content blocking stopped on the page's current document: how many
/// loads, from which sites. A new document starts the count again.
@MainActor
@Observable
final class BrowserPageBlockedLoads {
    /// Blocked loads per site.
    private(set) var countsBySite: [String: Int] = [:]
    /// Whether WebKit has reported anything on this page since it launched,
    /// so a page can tell "nothing blocked" from "nothing reported".
    private(set) var hasReports = false
    /// The load reported last and the lists that reported it.
    @ObservationIgnored private var lastLoad: (url: URL, ruleLists: Set<String>)?

    var total: Int { countsBySite.values.reduce(0, +) }

    /// The sites with blocked loads, most blocked first, then by name.
    var sites: [(site: String, count: Int)] {
        countsBySite.map { ($0.key, $0.value) }.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.site < $1.site
        }
    }

    /// Counts a load the rule list named `ruleList` blocked. WebKit reports a
    /// load once for each list that blocked it, one report after another, so
    /// a report of the same address from a list that has not reported it yet
    /// is the same load.
    func record(_ url: URL, by ruleList: String) {
        hasReports = true
        if let last = lastLoad, last.url == url, !last.ruleLists.contains(ruleList) {
            lastLoad?.ruleLists.insert(ruleList)
            return
        }
        lastLoad = (url, [ruleList])
        let site = BrowserSite.of(url) ?? url.absoluteString
        countsBySite[site, default: 0] += 1
    }

    func reset() {
        lastLoad = nil
        guard !countsBySite.isEmpty else { return }
        countsBySite = [:]
    }
}
