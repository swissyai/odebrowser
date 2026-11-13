import Foundation

enum BrowserUtilityListPreparation {
    static let searchDebounce = Duration.milliseconds(60)

    nonisolated static func nextRefreshDate(
        for request: BrowserUtilityListRequest,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let itemDates = baseItems(for: request).map(\.date)
        guard !itemDates.isEmpty else { return nil }

        var deadlines: [Date] = []
        let startOfToday = calendar.startOfDay(for: now)
        if let nextDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: startOfToday
        ) {
            deadlines.append(nextDay)
        }

        let activeFilter = request.filter.normalized(for: request.surface)
        deadlines += baseItems(for: request).compactMap { activeFilter.expiry(of: $0, in: calendar) }

        return deadlines.filter { $0 > now }.min()
    }

    /// The sections of `request`'s items, newest first. `history` holds the
    /// addresses a history reader found, which the core already matched to
    /// the search; without it, a history list shows the session's own
    /// entries that match.
    nonisolated static func sections(
        for request: BrowserUtilityListRequest,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        history: [HistoryPlace]? = nil
    ) -> [BrowserUtilityListSection] {
        guard let items = matchingItems(for: request, now: now, calendar: calendar, history: history) else {
            return []
        }
        let groupsBySite = request.surface == .history && request.historyGrouping.groupsBySite
        let sections =
            groupsBySite
            ? siteSections(of: items, now: now, calendar: calendar)
            : timeSections(of: items, now: now, calendar: calendar)
        return sections ?? []
    }

    /// `request`'s items that match its search and filter, newest first; the
    /// core's `history` places skip the search. Nil once the preparation is
    /// cancelled.
    nonisolated private static func matchingItems(
        for request: BrowserUtilityListRequest,
        now: Date,
        calendar: Calendar,
        history: [HistoryPlace]?
    ) -> [BrowserUtilityListItem]? {
        let query = request.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [BrowserUtilityListItem] = []
        let base = history?.map(BrowserUtilityListItem.history) ?? baseItems(for: request)
        for item in base {
            guard !Task.isCancelled else { return nil }
            guard history != nil || item.matches(query),
                matchesFilter(
                    item,
                    request: request,
                    now: now,
                    calendar: calendar
                )
            else { continue }
            items.append(item)
        }
        guard !Task.isCancelled else { return nil }
        items.sort { $0.date > $1.date }
        guard !Task.isCancelled else { return nil }
        return items
    }

    /// One section per site of the history `items`, in the order the sites
    /// first appear. A site is the host without `www.`, or the whole address
    /// when it has no host. Nil once the preparation is cancelled.
    nonisolated private static func siteSections(
        of items: [BrowserUtilityListItem],
        now: Date,
        calendar: Calendar
    ) -> [BrowserUtilityListSection]? {
        var sites: [String] = []
        var grouped: [String: [BrowserUtilityListItem]] = [:]
        for item in items {
            guard !Task.isCancelled else { return nil }
            guard case .history(let place) = item else { continue }
            let host = URL(string: place.url)?.host()?.lowercased() ?? place.url
            let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if grouped[site] == nil { sites.append(site) }
            grouped[site, default: []].append(item)
        }
        return sites.map { site in
            BrowserUtilityListSection(
                timeframe: BrowserUtilityTimeSection(date: now, now: now, calendar: calendar),
                items: grouped[site, default: []], site: site)
        }
    }

    /// One section per timeframe of `items`, in the order the timeframes
    /// first appear. Nil once the preparation is cancelled.
    nonisolated private static func timeSections(
        of items: [BrowserUtilityListItem],
        now: Date,
        calendar: Calendar
    ) -> [BrowserUtilityListSection]? {
        var timeframes: [BrowserUtilityTimeSection] = []
        var grouped: [BrowserUtilityTimeSection: [BrowserUtilityListItem]] = [:]
        for item in items {
            guard !Task.isCancelled else { return nil }
            let timeframe = BrowserUtilityTimeSection(
                date: item.date,
                now: now,
                calendar: calendar
            )
            if grouped[timeframe] == nil {
                timeframes.append(timeframe)
            }
            grouped[timeframe, default: []].append(item)
        }
        return timeframes.map { timeframe in
            BrowserUtilityListSection(
                timeframe: timeframe,
                items: grouped[timeframe, default: []]
            )
        }
    }

    nonisolated private static func baseItems(
        for request: BrowserUtilityListRequest
    ) -> [BrowserUtilityListItem] {
        request.surface.items(in: request)
    }

    nonisolated private static func matchesFilter(
        _ item: BrowserUtilityListItem,
        request: BrowserUtilityListRequest,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        request.filter.normalized(for: request.surface).includes(item, at: now, in: calendar)
    }
}
