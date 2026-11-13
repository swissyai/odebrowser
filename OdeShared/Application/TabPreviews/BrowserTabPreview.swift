import Foundation

// MARK: - Types

/// The mark a pinned or saved tab wears for its preview: how many messages
/// wait unread, or how soon the next event starts.
struct BrowserTabPreviewBadge: Equatable, Sendable {
    let text: String
    let accessibilityLabel: String
}

/// What one pinned or saved tab's site holds for the person right now, read
/// from the tab's own page: a mail site's unread messages, newest first, or a
/// calendar's events still to come, soonest first. It lives only in memory
/// and is never stored, synced or handed to an agent.
struct BrowserTabPreview: Equatable, Sendable {
    // MARK: - Types

    /// One message or event. A message names its sender; an event has a
    /// start and, unless it lasts all day, an end.
    struct Item: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        var sender: String? = nil
        var date: Date? = nil
        var endDate: Date? = nil
        var isAllDay = false
        /// Where the item opens in its tab, always on the tab's own site.
        var link: URL? = nil
    }

    // MARK: - Static Variables

    /// The most items a preview keeps.
    static let maximumItems = 20
    /// The highest count a badge spells out; more reads as this with a plus.
    static let badgeLimit = 99
    /// How long before an event starts its tab's badge counts down to it.
    static let countdownWindow: TimeInterval = 60 * 60
    /// How long an unread count stays on its tab's badge without a newer
    /// read, as while the tab sleeps; an event's time stays true.
    static let unreadCountLifetime: TimeInterval = 30 * 60

    // MARK: - Variables

    /// The account the page is signed in to, when the site names it.
    var account: String? = nil
    /// How many messages wait unread, for a mail site.
    var unreadCount: Int? = nil
    var items: [Item] = []
    /// The page is signed out, so its site shares nothing to preview.
    var isSignedOut = false
    /// When the page was read.
    let readAt: Date

    // MARK: - Actions - Reading

    /// The items still worth showing at `now`: every message, and the events
    /// that have not ended.
    func current(at now: Date) -> [Item] {
        items.filter { item in
            guard item.sender == nil, let date = item.date else { return true }
            return (item.endDate ?? date) > now || (item.isAllDay && Calendar.current.isDate(date, inSameDayAs: now))
        }
    }

    /// The tab's badge at `now`: the unread count for a mail site, while it
    /// was read within the last half hour, or for a calendar the minutes until
    /// an event that starts within the hour, and Now while one is under way.
    /// Nil when there is nothing to mark.
    func badge(at now: Date) -> BrowserTabPreviewBadge? {
        guard !isSignedOut else { return nil }
        if let unreadCount {
            guard unreadCount > 0, now.timeIntervalSince(readAt) <= Self.unreadCountLifetime else { return nil }
            let text =
                unreadCount > Self.badgeLimit
                ? String(
                    localized: "\(Self.badgeLimit)+",
                    comment: "A tab's unread count past its highest spelled-out number.")
                : unreadCount.formatted()
            return BrowserTabPreviewBadge(
                text: text,
                accessibilityLabel: String(
                    localized: "\(unreadCount) unread", comment: "Accessibility label of a tab's unread mail count."))
        }
        let timed = items.filter { $0.sender == nil && !$0.isAllDay }
        if let ongoing = timed.first(where: { ($0.date ?? .distantFuture) <= now && ($0.endDate ?? .distantPast) > now }
        ) {
            return BrowserTabPreviewBadge(
                text: String(localized: "Now", comment: "A calendar tab's badge while an event is under way."),
                accessibilityLabel: String(
                    localized: "\(ongoing.title) is under way",
                    comment: "Accessibility label of a calendar tab's badge."))
        }
        guard
            let next = timed.compactMap({ item in item.date.map { (item, $0) } }).filter({ $0.1 > now }).min(by: {
                $0.1 < $1.1
            }), next.1.timeIntervalSince(now) <= Self.countdownWindow
        else { return nil }
        let minutes = max(1, Int((next.1.timeIntervalSince(now) / 60).rounded(.up)))
        return BrowserTabPreviewBadge(
            text: Duration.seconds(minutes * 60).formatted(.units(allowed: [.minutes], width: .narrow)),
            accessibilityLabel: String(
                localized: "\(next.0.title) in \(minutes) minutes",
                comment: "Accessibility label of a calendar tab's badge."))
    }
}
