import Foundation

/// The downloads the foot of the sidebar shows for the shown Space, newest
/// first: every one still running or waiting for the person, and those that
/// ended unseen. A finished file stays for an hour after it finished, long
/// enough to drag it somewhere; a failed or blocked one stays until the
/// person looks. Opening the Downloads list, or hiding the recent ones, marks
/// them seen.
struct BrowserRecentDownloads: Equatable {
    // MARK: - Static Variables

    static let finishedLifetime: TimeInterval = 60 * 60
    /// The most rows the sidebar gives them; the rest wait in the list.
    static let maximumShown = 3

    // MARK: - Variables

    /// The rows the sidebar shows.
    let shown: [DownloadState]

    /// How many more recent downloads only the Downloads list shows.
    let moreCount: Int

    var isEmpty: Bool { shown.isEmpty }

    /// Whether any shown download has ended, which hiding them marks seen.
    var hasEnded: Bool { shown.contains { !$0.phase.isLive } }

    // MARK: - Initializers

    /// The recent ones among `items`, newest first, given when each ended.
    init(items: [DownloadState], endTime: (UUID) -> Date?, now: Date) {
        let recent = items.filter { Self.isRecent($0, endTime: endTime($0.id), now: now) }
        shown = Array(recent.prefix(Self.maximumShown))
        moreCount = recent.count - shown.count
    }

    // MARK: - Actions - Rules

    static func isRecent(_ item: DownloadState, endTime: Date?, now: Date) -> Bool {
        if item.phase.isLive { return true }
        guard !item.isAcknowledged else { return false }
        if item.phase.needsAttention || item.phase.awaitsDecision { return true }
        guard item.phase.isComplete else { return false }
        return now.timeIntervalSince(endTime ?? item.createdAt) <= finishedLifetime
    }

    /// Whether the sidebar shows `recent`: only while there are any, and not
    /// while the Downloads list, which holds them all, is open.
    static func isShown(_ recent: BrowserRecentDownloads, besides surface: BrowserUtilitySurface?) -> Bool {
        !recent.isEmpty && surface != .downloads
    }
}
