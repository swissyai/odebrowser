import Foundation

/// Presentation-only grouping for History; never changes Command Bar results.
struct BrowserHistoryGrouping: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let time = BrowserHistoryGrouping(id: "time", title: "Time", groupsBySite: false)
    static let site = BrowserHistoryGrouping(id: "site", title: "Site", groupsBySite: true)
    static let all = [time, site]

    // MARK: - Variables

    let id: String
    let title: LocalizedStringResource
    let groupsBySite: Bool

    // MARK: - Initializers

    private init(id: String, title: LocalizedStringResource, groupsBySite: Bool) {
        self.id = id
        self.title = title
        self.groupsBySite = groupsBySite
    }

    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
