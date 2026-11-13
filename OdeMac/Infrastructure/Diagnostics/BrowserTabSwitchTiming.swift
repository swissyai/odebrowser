/// One tab switch while it is timed, from the input that asked for it to the
/// arriving page's first frame, all on ``BrowserMoments/now``'s clock. The
/// departing page leaves the screen as the switch begins, unless its view is
/// held above the arriving one, and then when the hold ends; the frames that
/// pass after it left and before the arriving page drew are the switch's
/// blank frames.
struct BrowserTabSwitchTiming: Equatable, Sendable {
    // MARK: - Types

    struct Outcome: Equatable, Sendable {
        let milliseconds: Double
        let blankFrames: Int
    }

    // MARK: - Variables

    let began: UInt64
    /// One display frame, in nanoseconds.
    let frameInterval: UInt64
    var tags: BrowserMomentLedger.Tags
    /// When the departing page left the screen; nil while it is held there.
    private(set) var departed: UInt64?

    // MARK: - Initializers

    init(began: UInt64, framesPerSecond: Int, tags: BrowserMomentLedger.Tags) {
        self.began = began
        frameInterval = 1_000_000_000 / UInt64(max(1, framesPerSecond))
        self.tags = tags
        departed = began
    }

    // MARK: - Actions - Outcome

    /// The switch, had the arriving page drawn at `drawn`: how long it took,
    /// and the frames that showed neither page. A page that drew while the
    /// departing one was still held left no frame blank.
    func outcome(drawnAt drawn: UInt64) -> Outcome {
        let blankFrames = departed.map { drawn > $0 ? Int((drawn - $0) / frameInterval) : 0 } ?? 0
        return Outcome(
            milliseconds: drawn > began ? Double(drawn - began) / 1_000_000 : 0, blankFrames: blankFrames)
    }

    // MARK: - Mutators

    /// The departing page's view stays on screen above the arriving one.
    mutating func holdDeparture() {
        departed = nil
    }

    /// The held departing page left the screen at `time`.
    mutating func releaseDeparture(at time: UInt64) {
        guard departed == nil else { return }
        departed = max(time, began)
    }
}
