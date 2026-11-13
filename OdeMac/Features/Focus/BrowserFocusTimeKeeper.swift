import Foundation
import Observation

/// How long each site with a daily limit has been on screen today, counted
/// only while a window shows it and has the keyboard, and the extra minutes
/// the person took on it. The count stays on this Mac, starts again at
/// midnight, and is never synced or shared.
@Observable
@MainActor
final class BrowserFocusTimeKeeper {
    // MARK: - Types

    /// One day's count, as the defaults keep it.
    struct Day: Codable, Equatable {
        var date: String
        var seconds: [String: TimeInterval] = [:]
        var extraSeconds: [String: TimeInterval] = [:]
    }

    // MARK: - Static Variables

    static let shared = BrowserFocusTimeKeeper()
    /// What "Five More Minutes" adds.
    static let extraTime: TimeInterval = 5 * 60
    private static let defaultsKey = "browser.focus.day"

    // MARK: - Variables

    private(set) var day: Day
    /// The sites a window shows paused now.
    @ObservationIgnored var pausedOnScreen: Set<String> = []
    /// The site each window shows while it has the keyboard, and since when.
    @ObservationIgnored private var shown: [UUID: (site: String, since: Date)] = [:]
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var saving: Task<Void, Never>?

    // MARK: - Initializers

    /// A keeper whose count `defaults` keeps; with none, as in an isolated
    /// launch, it lives as long as the process.
    init(
        defaults: UserDefaults? = BrowserLaunchEnvironment.current.requiresIsolation ? nil : .standard,
        calendar: Calendar = .current, now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        let today = Self.date(of: now(), in: calendar)
        let kept = defaults?.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(Day.self, from: $0) }
        day = kept?.date == today ? kept! : Day(date: today)
    }

    // MARK: - Actions - Counting

    /// Counts `site` as shown in the window `windowID` from now on, or stops
    /// counting that window's site when `site` is nil.
    func show(_ site: String?, in windowID: UUID) {
        record()
        if let site { shown[windowID] = (site, now()) } else { shown.removeValue(forKey: windowID) }
        keepSaving()
    }

    /// How long `site` has been shown today, the time still counting included.
    func seconds(on site: String) -> TimeInterval {
        let today = Self.date(of: now(), in: calendar)
        let counted = day.date == today ? day.seconds[site, default: 0] : 0
        let running = shown.values.filter { $0.site == site }.reduce(0) {
            $0 + max(0, now().timeIntervalSince($1.since))
        }
        return counted + running
    }

    /// Whether `site` has used its daily `limit` and the extra time taken on it.
    func isPaused(_ site: String, limit: SiteTimeLimit?) -> Bool {
        guard let limit else { return false }
        return seconds(on: site) >= TimeInterval(limit.minutesPerDay * 60) + extraSeconds(on: site)
    }

    /// Gives `site` five more minutes from now, past its `limit`.
    func grantExtraTime(on site: String, limit: SiteTimeLimit) {
        record()
        let used = seconds(on: site) - TimeInterval(limit.minutesPerDay * 60)
        day.extraSeconds[site] = max(extraSeconds(on: site), used) + Self.extraTime
        save()
    }

    /// Adds `seconds` to today's count for `site`, as if it had been shown
    /// that long: the test harness's way to reach a limit without waiting.
    func count(_ seconds: TimeInterval, on site: String) {
        record()
        day.seconds[site, default: 0] += max(0, seconds)
        save()
    }

    private func extraSeconds(on site: String) -> TimeInterval {
        day.date == Self.date(of: now(), in: calendar) ? day.extraSeconds[site, default: 0] : 0
    }

    /// Adds the time shown so far to today's count, starting a new day after
    /// midnight.
    private func record() {
        let moment = now()
        let today = Self.date(of: moment, in: calendar)
        if day.date != today { day = Day(date: today) }
        for (windowID, entry) in shown {
            day.seconds[entry.site, default: 0] += max(0, moment.timeIntervalSince(entry.since))
            shown[windowID] = (entry.site, moment)
        }
        save()
    }

    /// While a site is counting, adds its time every half minute, so a quit
    /// loses little of it.
    private func keepSaving() {
        guard !shown.isEmpty else {
            saving?.cancel()
            saving = nil
            return
        }
        guard saving == nil else { return }
        saving = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                self.record()
            }
        }
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(day) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func date(of moment: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: moment)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
