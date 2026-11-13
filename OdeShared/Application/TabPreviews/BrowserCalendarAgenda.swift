import Foundation

/// The events a pinned Google Calendar tab's page shows, as its reader
/// collects them from the page: each event's id, the label the page gives it
/// for screen readers, such as "10am to 10:30am, Design review, Jane Doe,
/// Accepted, No location, November 3, 2026", and the day of the column it
/// sits in. Events the person declined are left out, as is a label in a form
/// the reader does not know, such as one in another language.
enum BrowserCalendarAgenda {
    // MARK: - Types

    private struct Answer: Decodable {
        let account: String?
        let events: [Chip]
    }

    /// One event as the page shows it.
    fileprivate struct Chip: Decodable {
        let id: String
        let label: String
        /// The page's key for the column's day: years since 1970, the month
        /// and the day, packed as `year << 9 | month << 5 | day`.
        let day: Int?
    }

    /// A time of day in a label, such as "10", "10:30am" or "14:00".
    fileprivate struct ClockTime {
        let hour: Int
        let minute: Int
        let isPM: Bool?
    }

    // MARK: - Static Variables

    /// How a label spells an event that lasts the day.
    static let allDay = "all day"
    /// How a label marks an event the person declined.
    static let declined = "declined"
    /// The event ids a link may carry.
    static let idCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=")

    // MARK: - Actions - Reading

    /// The preview the calendar reader's `answer`, its JSON text, describes,
    /// read at `readAt`, with each event opening under `home`, the tab's
    /// calendar address such as `https://calendar.google.com/calendar/u/0/`.
    /// Nil for an answer in another shape.
    static func preview(
        answer: Data, home: URL, readAt: Date, calendar: Calendar = .current
    ) -> BrowserTabPreview? {
        guard let answer = try? JSONDecoder().decode(Answer.self, from: answer) else { return nil }
        let items = answer.events.compactMap { $0.item(home: home, calendar: calendar) }
            .sorted { ($0.date ?? .distantFuture, $0.title) < ($1.date ?? .distantFuture, $1.title) }
        return BrowserTabPreview(
            account: answer.account, items: Array(items.prefix(BrowserTabPreview.maximumItems)), readAt: readAt)
    }
}

extension BrowserCalendarAgenda.Chip {
    // MARK: - Actions - Items

    /// The event as a preview item, or nil when it was declined or its label
    /// cannot be read.
    fileprivate func item(home: URL, calendar: Calendar) -> BrowserTabPreview.Item? {
        let parts = label.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, !parts.contains(where: { $0.lowercased() == BrowserCalendarAgenda.declined }),
            let day = day.flatMap({ Self.date(fromKey: $0, calendar: calendar) })
                ?? Self.date(in: parts, calendar: calendar)
        else { return nil }
        let title =
            parts[1].isEmpty ? String(localized: "(No title)", comment: "A calendar event without a title.") : parts[1]
        let link =
            id.unicodeScalars.allSatisfy(BrowserCalendarAgenda.idCharacters.contains) && !id.isEmpty
            ? URL(string: "r/eventedit/\(id)", relativeTo: home)?.absoluteURL : nil
        if parts[0].lowercased() == BrowserCalendarAgenda.allDay {
            return BrowserTabPreview.Item(id: id, title: title, date: day, isAllDay: true, link: link)
        }
        guard let (start, end) = Self.times(in: parts[0]),
            let startDate = calendar.date(bySettingHour: start.hour, minute: start.minute, second: 0, of: day),
            var endDate = calendar.date(bySettingHour: end.hour, minute: end.minute, second: 0, of: day)
        else { return nil }
        if endDate <= startDate { endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate }
        return BrowserTabPreview.Item(id: id, title: title, date: startDate, endDate: endDate, link: link)
    }

    /// The day a column key names, at the start of that day.
    fileprivate static func date(fromKey key: Int, calendar: Calendar) -> Date? {
        let components = DateComponents(year: (key >> 9) + 1970, month: (key >> 5) & 15, day: key & 31)
        guard components.month.map((1...12).contains) == true, components.day.map((1...31).contains) == true else {
            return nil
        }
        return calendar.date(from: components)
    }

    /// The day a label names at its end, as in "November 3, 2026".
    fileprivate static func date(in parts: [String], calendar: Calendar) -> Date? {
        guard parts.count >= 3, let year = Int(parts[parts.count - 1]), (1970...9999).contains(year) else { return nil }
        let monthAndDay = parts[parts.count - 2].split(separator: " ")
        guard monthAndDay.count == 2, let day = Int(monthAndDay[1]),
            let month = calendar.monthSymbols.firstIndex(where: {
                $0.compare(String(monthAndDay[0]), options: .caseInsensitive) == .orderedSame
            })
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month + 1, day: day))
    }

    /// The start and end a label's first part names, as in "10 to 11am",
    /// "11:30am to 1pm" or "14:00 to 15:30". A start without its half of the
    /// day takes the end's, unless that would put it after the end.
    fileprivate static func times(
        in text: String
    ) -> (start: (hour: Int, minute: Int), end: (hour: Int, minute: Int))? {
        let bounds = text.lowercased().components(separatedBy: " to ")
        guard bounds.count == 2, let first = BrowserCalendarAgenda.ClockTime(bounds[0]),
            let last = BrowserCalendarAgenda.ClockTime(bounds[1])
        else { return nil }
        let end = last.hours(isPM: last.isPM)
        var start = first.hours(isPM: first.isPM ?? last.isPM)
        if first.isPM == nil, last.isPM == true, start.hour * 60 + start.minute > end.hour * 60 + end.minute {
            start = first.hours(isPM: false)
        }
        return (start, end)
    }
}

extension BrowserCalendarAgenda.ClockTime {
    // MARK: - Initializers

    /// A time of day as a label spells it, or nil for anything else.
    fileprivate init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespaces)
        var isPM: Bool?
        for (suffix, pm) in [("am", false), ("pm", true)] where text.hasSuffix(suffix) {
            isPM = pm
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        let pieces = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(pieces.count), let hour = Int(pieces[0]),
            let minute = pieces.count == 2 ? Int(pieces[1]) : 0, (0...59).contains(minute),
            isPM == nil ? (0...23).contains(hour) : (1...12).contains(hour)
        else { return nil }
        self.init(hour: hour, minute: minute, isPM: isPM)
    }

    // MARK: - Actions - Hours

    /// The time on a 24-hour clock, in the half of the day `isPM` names when
    /// the time came with one.
    fileprivate func hours(isPM: Bool?) -> (hour: Int, minute: Int) {
        guard let isPM else { return (hour, minute) }
        return ((hour % 12) + (isPM ? 12 : 0), minute)
    }
}
