import Foundation

extension HistoryPlace {
    /// The address a history entry the session holds stands for.
    init(_ entry: HistoryEntryState) {
        self.init(
            url: entry.url, title: entry.title, firstVisitedAt: entry.firstVisitedAt,
            lastVisitedAt: entry.lastVisitedAt, visitCount: entry.visitCount)
    }
}
