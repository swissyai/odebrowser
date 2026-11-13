import Foundation

/// Whether a page answers. After the person clicks in it or types into it,
/// Ode asks the page's document a trivial question; a page that has not
/// answered within ``frozenAfter`` of the person's first unanswered
/// interaction is frozen, and the window offers to wait or stop it. Nothing
/// runs on a page nobody touches, and a page off screen counts nothing.
struct BrowserPageResponsiveness: Equatable, Sendable {
    // MARK: - Static Variables

    /// How long an interaction may go unanswered before the page is frozen.
    static let frozenAfter: TimeInterval = 10
    /// How long choosing to wait keeps the offer away.
    static let waitingTime: TimeInterval = 30
    /// How long after the Mac wakes nothing counts as frozen: a page that was
    /// busy when the Mac slept answers once it catches up.
    static let wakeGrace: TimeInterval = 15

    // MARK: - Variables

    /// The question out to the document, numbered so a late answer to an
    /// earlier one changes nothing; nil while none is out.
    private(set) var question: Int?
    /// When the person first interacted without an answer since; nil while
    /// nothing waits.
    private(set) var waitingSince: Date?
    private(set) var silencedUntil: Date?
    private var asked = 0

    // MARK: - Mutators

    /// The person clicked in the page or typed into it at `now`. Answers the
    /// number of the question to ask the document, or nil while one is out.
    mutating func interacted(at now: Date) -> Int? {
        if waitingSince == nil { waitingSince = now }
        guard question == nil else { return nil }
        asked &+= 1
        question = asked
        return asked
    }

    /// The document answered `answered`: the page responds.
    mutating func answered(_ answered: Int) {
        guard question == answered else { return }
        question = nil
        waitingSince = nil
        silencedUntil = nil
    }

    /// The page left the screen: nothing counts until the person interacts
    /// with it again.
    mutating func hidden() {
        waitingSince = nil
        silencedUntil = nil
    }

    /// The person chose to wait at `now`.
    mutating func wait(at now: Date) {
        silencedUntil = now.addingTimeInterval(Self.waitingTime)
    }

    /// The page was stopped: whatever was out is forgotten.
    mutating func reset() {
        question = nil
        waitingSince = nil
        silencedUntil = nil
    }

    // MARK: - Actions - Reading

    /// Whether the window offers to wait or stop the page at `now`, given
    /// when the Mac last woke from sleep.
    func isFrozen(at now: Date, lastWake: Date? = nil) -> Bool {
        guard question != nil, var since = waitingSince else { return false }
        if let lastWake {
            if now.timeIntervalSince(lastWake) < Self.wakeGrace { return false }
            since = max(since, lastWake)
        }
        if let silencedUntil, now < silencedUntil { return false }
        return now.timeIntervalSince(since) >= Self.frozenAfter
    }
}
