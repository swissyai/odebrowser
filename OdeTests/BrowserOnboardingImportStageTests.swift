import XCTest

@testable import Ode

/// The import stage never adds waiting and never claims what the import has
/// not done: its beats fit in 2.4 s, it leaves within 0.6 s of the import
/// finishing, its counts come from the Spaces it brings, and it says when the
/// import stalls.
@MainActor
final class BrowserOnboardingImportStageTests: XCTestCase {
    private typealias Choreography = BrowserOnboardingImportChoreography

    // MARK: - Choreography

    func testFlightsStaggerFromTheSettledStageAndLandInOrder() {
        let beats = Choreography(flightCount: 8, spaceCount: 1, reducesMotion: false)

        XCTAssertEqual(beats.flightStart(0), 0.32, accuracy: 0.0001)
        XCTAssertEqual(beats.flightStart(7), 0.32 + 7 * 0.045, accuracy: 0.0001)
        XCTAssertEqual(beats.firstLanding, 0.74, accuracy: 0.0001)
        XCTAssertEqual(beats.lastLanding, 0.32 + 7 * 0.045 + 0.42, accuracy: 0.0001)
        XCTAssertEqual(beats.firstSpaceWhole, max(0.74 + 0.36, beats.lastLanding + 0.2), accuracy: 0.0001)
        XCTAssertEqual(beats.end, beats.firstSpaceWhole, accuracy: 0.0001)
    }

    func testEveryBeatEndsWithinTheCap() {
        for flights in 0...12 {
            for spaces in 0...6 {
                for reduces in [false, true] {
                    let beats = Choreography(flightCount: flights, spaceCount: spaces, reducesMotion: reduces)
                    XCTAssertLessThanOrEqual(beats.end, Choreography.cap, "\(flights) \(spaces) \(reduces)")
                    XCTAssertGreaterThan(beats.end, 0)
                    if beats.spaceCount > 1 {
                        let swipe = reduces ? Choreography.reducedFade : Choreography.nextSpace
                        XCTAssertEqual(
                            beats.end, beats.spaceStart(beats.spaceCount - 1) + swipe, accuracy: 0.0001,
                            "The last Space shown always arrives whole.")
                    }
                }
            }
        }
    }

    func testCountsAreHeldToWhatTheStageShows() {
        let beats = Choreography(flightCount: 20, spaceCount: 9, reducesMotion: false)
        XCTAssertEqual(beats.flightCount, Choreography.maximumFlights)
        XCTAssertLessThanOrEqual(beats.spaceCount, Choreography.maximumShownSpaces)
        XCTAssertEqual(Choreography(flightCount: 0, spaceCount: 9, reducesMotion: true).spaceCount, 3)
        XCTAssertEqual(
            Choreography(flightCount: 8, spaceCount: 9, reducesMotion: false).spaceCount, 2,
            "A third Space would arrive after the cap.")
        XCTAssertEqual(Choreography(flightCount: -1, spaceCount: 0, reducesMotion: false).spaceCount, 1)
    }

    func testNextSpacesComeInAfterTheFirstIsWholeAndInOrder() {
        let beats = Choreography(flightCount: 2, spaceCount: 2, reducesMotion: false)

        XCTAssertEqual(beats.spaceCount, 2)
        XCTAssertEqual(beats.spaceStart(0), 0)
        XCTAssertEqual(beats.spaceStart(1), beats.firstSpaceWhole + Choreography.spaceHold, accuracy: 0.0001)
        XCTAssertGreaterThan(beats.spaceStart(2), beats.spaceStart(1) + Choreography.nextSpace)
    }

    func testReduceMotionFliesNothingAndFadesEachSpaceIn() {
        let beats = Choreography(flightCount: 8, spaceCount: 2, reducesMotion: true)

        XCTAssertEqual(beats.flightCount, 0)
        XCTAssertEqual(beats.settled, Choreography.reducedFade)
        XCTAssertEqual(beats.firstSpaceWhole, Choreography.reducedFade * 2, accuracy: 0.0001)
        XCTAssertLessThan(beats.end, Choreography(flightCount: 8, spaceCount: 2, reducesMotion: false).end)
    }

    func testTheStageNeverOutlastsTheImportByMoreThanTheFinishCap() {
        let beats = Choreography(flightCount: 8, spaceCount: 3, reducesMotion: false)

        XCTAssertEqual(beats.dismissal(doneAt: 0.1), 0.1 + Choreography.finishCap, accuracy: 0.0001)
        XCTAssertEqual(beats.dismissal(doneAt: 1.9), min(beats.end, 2.5), accuracy: 0.0001)
        XCTAssertEqual(beats.dismissal(doneAt: 1.2), min(beats.end, 1.8), accuracy: 0.0001)
        XCTAssertEqual(beats.dismissal(doneAt: 30), 30, "A slow import leaves as soon as it is done.")
    }

    func testProgressIsClampedAndInstantForAZeroBeat() {
        XCTAssertEqual(Choreography.progress(at: 0.5, start: 1, duration: 1), 0)
        XCTAssertEqual(Choreography.progress(at: 1.5, start: 1, duration: 1), 0.5)
        XCTAssertEqual(Choreography.progress(at: 3, start: 1, duration: 1), 1)
        XCTAssertEqual(Choreography.progress(at: 1, start: 1, duration: 0), 1)
    }

    // MARK: - Stage

    func testTheStageCountsWhatEachSpaceBringsAndFliesPinnedFirst() throws {
        let stage = makeStage()
        let work = try XCTUnwrap(stage.spaces.first { $0.name == "Work" })

        XCTAssertEqual(work.tabCount, 13)
        XCTAssertEqual(work.pinnedCount, 3)
        XCTAssertEqual(work.flights.count, Choreography.maximumFlights)
        XCTAssertEqual(work.flights.prefix(3).map(\.placement), [.pinned, .pinned, .pinned])
        XCTAssertEqual(work.countLine, "Work · 13 tabs · 3 pinned")
        XCTAssertEqual(stage.spaces.first { $0.name == "Home" }?.countLine, "Home · 1 tab")
    }

    func testTheLineSaysWhatTheImportDoesThenWhatCameOver() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let stage = makeStage(passwords: 12, readsKeychain: true, at: start)

        XCTAssertEqual(stage.statusLine(at: start), "Reading passwords from Arc")
        XCTAssertFalse(stage.isStalled(at: start.addingTimeInterval(7.9)))
        XCTAssertTrue(stage.isStalled(at: start.addingTimeInterval(8)))
        XCTAssertTrue(stage.statusLine(at: start.addingTimeInterval(9)).hasPrefix("Still waiting"))

        stage.bringing(at: start.addingTimeInterval(9))
        XCTAssertFalse(stage.isStalled(at: start.addingTimeInterval(10)), "News resets the stall.")
        XCTAssertEqual(stage.statusLine(at: start.addingTimeInterval(10)), "Bringing 12 passwords and 2 Spaces")

        stage.finish(passwords: 11, at: start.addingTimeInterval(11))
        XCTAssertEqual(stage.statusLine(at: start.addingTimeInterval(30)), "2 Spaces · 14 tabs · 11 passwords")
        XCTAssertFalse(stage.isStalled(at: start.addingTimeInterval(30)), "A finished import never stalls.")
        XCTAssertEqual(stage.doneAt, start.addingTimeInterval(11))
    }

    func testSkippingJumpsToTheEndWithoutFinishingTheImport() {
        let stage = makeStage()
        stage.skip()
        XCTAssertTrue(stage.isSkipped)
        XCTAssertFalse(stage.isDone)
    }

    // MARK: - Fixtures

    private func makeStage(
        passwords: Int = 0, readsKeychain: Bool = false, at date: Date = .now
    ) -> BrowserOnboardingImportStage {
        let site = { (name: String, placement: TabPlacement) in
            TabState.Seed(
                title: name, url: URL(string: "https://\(name.lowercased()).example"), placement: placement)
        }
        let work = SpaceState.Seed(
            name: "Work",
            tabs: ["Mail", "Calendar", "Docs"].map { site($0, .pinned) }
                + (1...6).map { site("Saved \($0)", .saved) }
                + (1...4).map { site("Open \($0)", .current) })
        let home = SpaceState.Seed(name: "Home", tabs: [site("Recipes", .current)])
        let browser = BrowserStore(seed: SessionState.Seed(spaces: [work, home]))
        return BrowserOnboardingImportStage(
            sourceTitle: "Arc", sourceIcon: nil, favicons: browser.core.state.favicons,
            spaces: browser.spaceModels, passwordCount: passwords, readsKeychain: readsKeychain, leftOut: [],
            startedAt: date)
    }
}
