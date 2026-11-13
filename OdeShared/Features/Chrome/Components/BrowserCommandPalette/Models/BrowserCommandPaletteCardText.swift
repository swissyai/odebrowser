import Foundation

/// What a card writes in the person's own formats: a time card's time and
/// day in its zone, the time a person gave in the zone they gave it in, and
/// what Return copies from a card.
enum BrowserCommandPaletteCardText {
    // MARK: - Actions - Writing

    /// The time `clock` tells, in its zone, as "11:05 PM".
    static func time(_ clock: PaletteCardClock) -> String {
        clock.instant.formatted(Date.FormatStyle(timeZone: zone(clock.zone)).hour().minute())
    }

    /// The day `clock` falls on in its zone, as "Tuesday, November 3".
    static func day(_ clock: PaletteCardClock) -> String {
        clock.instant.formatted(Date.FormatStyle(timeZone: zone(clock.zone)).weekday(.wide).month(.wide).day())
    }

    /// The time a person gave, in the place they gave it, as "3:00 PM in New
    /// York", or nil for the time now.
    static func given(_ clock: PaletteCardClock) -> String? {
        guard let fromZone = clock.fromZone, let fromPlace = clock.fromPlace else { return nil }
        let time = clock.instant.formatted(Date.FormatStyle(timeZone: zone(fromZone)).hour().minute())
        return String(localized: "\(time) in \(fromPlace)")
    }

    /// What Return copies from `card`: a time card's time, else its value.
    static func copied(_ card: PaletteCard) -> String? {
        if let clock = card.clock { return time(clock) }
        return card.value
    }

    private static func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? .current
    }
}
