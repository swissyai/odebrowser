import Foundation

/// The times Ode's main thread stopped answering, as the watchdog measured
/// them: each day's count, total and longest for every hang of
/// ``recorded`` or more, and each hang of ``long`` or more on its own, for
/// the crash and hang reports. Nothing here names a page or what Ode was
/// doing; only when and for how long.
///
/// The file is `hangs.json` beside the session, version 1:
///
///     {"version":1,"days":[{"day":"2026-10-29","count":3,"totalSeconds":2.1,
///       "longestSeconds":1.2}],"long":[{"at":"2026-10-29T09:12:03Z","seconds":4.5}]}
struct BrowserHangLog: Codable, Equatable, Sendable {
    // MARK: - Types

    struct Day: Codable, Equatable, Sendable {
        let day: String
        var count: Int
        var totalSeconds: Double
        var longestSeconds: Double
    }

    struct Hang: Codable, Equatable, Sendable {
        let at: Date
        let seconds: Double
    }

    // MARK: - Static Variables

    static let currentVersion = 1
    static let fileName = "hangs.json"
    /// The shortest stall that counts as a hang, as Apple measures them.
    static let recorded: TimeInterval = 0.25
    /// A hang long enough to keep on its own and report.
    static let long: TimeInterval = 3
    static let daysKept = 14
    static let longKept = 50

    // MARK: - Variables

    var version = currentVersion
    var days: [Day] = []
    var long: [Hang] = []

    // MARK: - Mutators

    /// Counts a hang of `seconds` that began at `start`. Shorter stalls than
    /// ``recorded`` are not hangs and change nothing.
    mutating func record(start: Date, seconds: TimeInterval, calendar: Calendar = .current) {
        guard seconds >= Self.recorded else { return }
        let day = Self.dayName(start, calendar: calendar)
        if let index = days.lastIndex(where: { $0.day == day }) {
            days[index].count += 1
            days[index].totalSeconds += seconds
            days[index].longestSeconds = max(days[index].longestSeconds, seconds)
        } else {
            days.append(Day(day: day, count: 1, totalSeconds: seconds, longestSeconds: seconds))
            days.sort { $0.day < $1.day }
            if days.count > Self.daysKept { days.removeFirst(days.count - Self.daysKept) }
        }
        if seconds >= Self.long {
            long.append(Hang(at: start, seconds: seconds))
            if long.count > Self.longKept { long.removeFirst(long.count - Self.longKept) }
        }
    }

    private static func dayName(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - Actions - Files

    /// The log beside the session in `directory`; an empty one when it is
    /// missing or cannot be read.
    static func read(in directory: URL, files: any BrowserLaunchRecordFiles = BrowserLaunchRecordDisk()) -> Self {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? files.read(url), let log = try? decoder.decode(Self.self, from: data),
            log.version == currentVersion
        else { return Self() }
        return log
    }

    /// Writes the log beside the session in `directory`, whole.
    func write(in directory: URL, files: any BrowserLaunchRecordFiles = BrowserLaunchRecordDisk()) {
        guard let data = try? Self.encoder.encode(self) else { return }
        try? files.writeDurably(data, to: directory.appendingPathComponent(Self.fileName))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
