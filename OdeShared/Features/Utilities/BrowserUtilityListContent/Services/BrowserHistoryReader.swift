import Foundation

/// Reads a Space's history from the core, which keeps every visit beside the
/// session: the newest addresses first, or those whose words match a search,
/// a page at a time and away from the main thread. A list that reads through
/// it reads again whenever `revision` moves.
struct BrowserHistoryReader: Sendable {
    // MARK: - Static Variables

    /// How many addresses a list shows before it reads more.
    static let pageSize = 500

    // MARK: - Variables

    let core: OdeCore
    let workspaceID: UUID

    /// Moves whenever the history kept beside the session changes.
    @MainActor var revision: Int64 { core.state.storedHistoryRevision }

    // MARK: - Actions - Reading

    /// Up to `limit` addresses of `spaceID`, newest first, or those whose
    /// title or address hold the words of `text`, best first, and whether
    /// more follow. A refused query throws; partial rows must not masquerade
    /// as a complete successful result, including a later page's failure.
    nonisolated func places(in spaceID: UUID, matching text: String, limit: Int) throws(Rejection) -> HistoryPlaces {
        var places: [HistoryPlace] = []
        var before: Date?
        var beforeURL: String?
        while places.count < limit {
            let question = HistoryList(
                workspaceID: workspaceID, spaceID: spaceID, text: text, before: before,
                limit: min(limit - places.count, HistoryList.maximumLimit), beforeURL: beforeURL)
            let answer = try core.query(question)
            places += answer.places
            guard answer.hasMore, let last = answer.places.last else {
                return HistoryPlaces(places: places, hasMore: false)
            }
            before = last.lastVisitedAt
            beforeURL = last.url
        }
        return HistoryPlaces(places: places, hasMore: true)
    }
}
