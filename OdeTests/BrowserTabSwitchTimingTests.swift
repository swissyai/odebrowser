import XCTest

@testable import Ode

/// How a tab switch is timed: from the input to the arriving page's first
/// frame, with the frames that showed neither page counted.
@MainActor
final class BrowserTabSwitchTimingTests: XCTestCase {
    private let millisecond: UInt64 = 1_000_000
    private let loaded = BrowserMomentLedger.Tags(engine: "chromium", slept: false, local: true)

    func testAPageThatDrawsWhileTheDepartingOneIsHeldLeavesNoFrameBlank() {
        var timing = BrowserTabSwitchTiming(began: 1_000 * millisecond, framesPerSecond: 120, tags: loaded)
        timing.holdDeparture()
        XCTAssertEqual(
            timing.outcome(drawnAt: 1_030 * millisecond),
            .init(milliseconds: 30, blankFrames: 0), "The held page covered every frame until the draw.")

        timing.releaseDeparture(at: 1_042 * millisecond)
        XCTAssertEqual(
            timing.outcome(drawnAt: 1_030 * millisecond).blankFrames, 0, "A draw before the release is not late.")
        XCTAssertEqual(
            timing.outcome(drawnAt: 1_067 * millisecond).blankFrames, 3,
            "25 ms after the release at 120 Hz is three frames that showed neither page.")
    }

    func testWithoutAHoldTheDepartingPageLeavesAsTheSwitchBegins() {
        let timing = BrowserTabSwitchTiming(began: 2_000 * millisecond, framesPerSecond: 60, tags: loaded)
        let outcome = timing.outcome(drawnAt: 2_050 * millisecond)
        XCTAssertEqual(outcome.milliseconds, 50)
        XCTAssertEqual(outcome.blankFrames, 3, "50 ms at 60 Hz is three whole frames.")
        XCTAssertEqual(timing.outcome(drawnAt: 1_990 * millisecond), .init(milliseconds: 0, blankFrames: 0))
    }

    func testTheClockRecordsTheArrivingPagesFirstFrameAndIgnoresOtherPages() {
        let moments = BrowserMoments()
        let clock = BrowserTabSwitchClock(moments: moments)
        let arriving = NSObject()
        let departing = NSObject()
        let start = BrowserMoments.now
        clock.began(arriving: arriving, at: start, framesPerSecond: 120, tags: loaded)
        clock.departureHeld()
        clock.drew(departing, at: start + 5 * millisecond)
        XCTAssertEqual(moments.ledger.count(.tabSwitch), 0, "Only the arriving page ends the switch.")
        clock.departed(at: start + 42 * millisecond)
        clock.drew(arriving, at: start + 60 * millisecond)
        clock.drew(arriving, at: start + 90 * millisecond)

        XCTAssertEqual(moments.ledger.count(.tabSwitch), 1, "A switch ends once.")
        XCTAssertEqual(moments.ledger.statistics(.tabSwitch)?.median, 60)
        XCTAssertEqual(moments.ledger.value(.blankFrames), 2)
        XCTAssertEqual(moments.ledger.statistics(.tabSwitch, label: "engine=chromium")?.count, 1)
        XCTAssertEqual(moments.ledger.statistics(.tabSwitch, label: "slept=false")?.count, 1)

        clock.began(arriving: arriving, at: start + 100 * millisecond, framesPerSecond: 120, tags: loaded)
        clock.began(arriving: departing, at: start + 110 * millisecond, framesPerSecond: 120, tags: loaded)
        clock.drew(arriving, at: start + 120 * millisecond)
        XCTAssertEqual(moments.ledger.count(.tabSwitch), 1, "A switch the next one overtook records nothing.")
    }
}
