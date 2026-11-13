import Foundation

/// When one tab's preview is read: as soon as its page can be, again each
/// time the page finishes a new document, and otherwise once per its site's
/// refresh interval. A read that fails, as on a page still drawing, is tried
/// again soon and then less and less often. Hovering the tab asks for a read
/// only when the preview is no longer fresh.
struct BrowserTabPreviewTiming: Equatable, Sendable {
    // MARK: - Static Variables

    /// How long after a first failed read the next is tried; each further
    /// failure doubles it.
    static let retryDelay: TimeInterval = 15
    /// The longest a failing tab waits between reads.
    static let maximumRetryDelay: TimeInterval = 30 * 60
    /// How old a preview may be before hovering its tab reads it again.
    static let hoverFreshness: TimeInterval = 30

    // MARK: - Variables

    private(set) var lastAttempt: Date?
    private(set) var lastSuccess: Date?
    /// Failed reads since the last one that succeeded.
    private(set) var failures = 0
    /// The page's document generation the last read began in.
    private(set) var generation: Int?

    // MARK: - Actions - Scheduling

    /// When the next read is due, for a site read every `interval`; nil
    /// before the first.
    func nextRead(every interval: TimeInterval) -> Date? {
        guard let lastAttempt else { return nil }
        guard failures > 0 else { return lastAttempt.addingTimeInterval(interval) }
        let delay = Self.retryDelay * pow(2, Double(min(failures, 16) - 1))
        return lastAttempt.addingTimeInterval(min(delay, Self.maximumRetryDelay))
    }

    /// Whether a page in document `generation` is due a read at `now`.
    func isDue(at now: Date, every interval: TimeInterval, generation: Int) -> Bool {
        guard let next = nextRead(every: interval) else { return true }
        return generation != self.generation || now >= next
    }

    /// Whether a preview read last is recent enough that hovering its tab at
    /// `now` reads nothing.
    func isFresh(at now: Date) -> Bool {
        lastSuccess.map { now.timeIntervalSince($0) < Self.hoverFreshness } ?? false
    }

    // MARK: - Mutators

    mutating func begin(at now: Date, generation: Int) {
        lastAttempt = now
        self.generation = generation
    }

    mutating func succeed(at now: Date) {
        lastSuccess = now
        failures = 0
    }

    mutating func fail() {
        failures += 1
    }
}
