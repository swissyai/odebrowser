import AppKit
import XCTest

@testable import Ode

/// The moments ledger Ode keeps on the Mac: what it counts, the recent
/// samples it keeps, the statistics a release gate reads, and its file.
final class BrowserMomentLedgerTests: XCTestCase {
    private typealias Ledger = BrowserMomentLedger

    func testPercentilesAreNearestRankOverTheRecentSamples() throws {
        var ledger = Ledger()
        for milliseconds in [40.0, 10, 30, 20, 50, 60, 70, 80, 90, 100] {
            ledger.record(.tabSwitch, milliseconds: milliseconds)
        }
        let statistics = try XCTUnwrap(ledger.statistics(.tabSwitch))
        XCTAssertEqual(statistics.count, 10)
        XCTAssertEqual(statistics.median, 50, "The 5th of 10 sorted durations is the median.")
        XCTAssertEqual(statistics.p95, 100, "The 10th of 10 sorted durations is the 95th percentile.")
        XCTAssertEqual(statistics.max, 100)
        XCTAssertNil(ledger.statistics(.commandBarOpen), "A moment never recorded has no statistics.")

        let one = try XCTUnwrap(Ledger.Statistics([7]))
        XCTAssertEqual([one.median, one.p95, one.max], [7, 7, 7])
    }

    func testOnlyTheNewestSamplesAreKeptWhileEveryMomentIsCounted() throws {
        var ledger = Ledger()
        for index in 0..<(Ledger.recentKept + 50) {
            ledger.record(.commandBarOpen, milliseconds: Double(index))
        }
        let entry = try XCTUnwrap(ledger.moments[Ledger.Kind.commandBarOpen.rawValue])
        XCTAssertEqual(entry.count, Ledger.recentKept + 50)
        XCTAssertEqual(entry.recent.count, Ledger.recentKept)
        XCTAssertEqual(entry.recent.first?.milliseconds, 50, "The oldest samples go first.")
        XCTAssertEqual(entry.longestMilliseconds, Double(Ledger.recentKept + 49))
        XCTAssertEqual(ledger.statistics(.commandBarOpen)?.count, Ledger.recentKept)

        ledger.record(.commandBarOpen, milliseconds: -1)
        ledger.record(.commandBarOpen, milliseconds: .nan)
        XCTAssertEqual(
            ledger.count(.commandBarOpen), Ledger.recentKept + 50, "A duration that is no duration is dropped.")
    }

    func testTagsGroupSamplesAndCountersStayWithTheirMoment() throws {
        var ledger = Ledger()
        ledger.record(.tabSwitch, milliseconds: 20, tags: .init(engine: "chromium", slept: false, local: true))
        ledger.record(.tabSwitch, milliseconds: 40, tags: .init(engine: "webkit", slept: false, local: true))
        ledger.record(.tabSwitch, milliseconds: 400, tags: .init(engine: "webkit", slept: true, local: false))
        ledger.count(.blankFrames, by: 0)
        ledger.count(.blankFrames, by: 2)
        ledger.count(.undrawn)

        XCTAssertEqual(ledger.statistics(.tabSwitch, label: "slept=false")?.p95, 40)
        XCTAssertEqual(ledger.statistics(.tabSwitch, label: "engine=webkit")?.count, 2)
        XCTAssertEqual(ledger.value(.blankFrames), 2)
        XCTAssertEqual(ledger.value(.undrawn), 1)
        XCTAssertEqual(ledger.value(.restoreDifferences), 0)

        let summary = try XCTUnwrap(ledger.summary.moments[Ledger.Kind.tabSwitch.rawValue])
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.median, 40)
        XCTAssertEqual(summary.max, 400)
        XCTAssertEqual(summary.counters, ["blankFrames": 2, "undrawn": 1])
        XCTAssertEqual(summary.tags["slept=true"]?.median, 400)
        XCTAssertEqual(summary.tags["local=true"]?.count, 2)

        ledger.count(.typedTextSlept, by: 0)
        let counted = try XCTUnwrap(ledger.summary.moments[Ledger.Kind.wake.rawValue])
        XCTAssertEqual(counted.count, 0)
        XCTAssertNil(counted.median, "A counter alone lists its moment without statistics.")
        XCTAssertEqual(counted.counters, ["typedTextSlept": 0])
    }

    func testAPageIsLocalWhenItComesFromThisMac() {
        let local = [
            "file:///tmp/a.html", "about:blank", "http://127.0.0.1:8080/a", "http://localhost/a", "http://[::1]/",
        ]
        for address in local { XCTAssertEqual(Ledger.Tags.isLocal(URL(string: address)), true, address) }
        for address in ["https://example.com/", "http://192.168.1.4/"] {
            XCTAssertEqual(Ledger.Tags.isLocal(URL(string: address)), false, address)
        }
        XCTAssertNil(Ledger.Tags.isLocal(nil))
    }

    func testTheLedgerIsKeptBesideTheSessionAndAnUnreadableOneStartsEmpty() throws {
        var ledger = Ledger()
        ledger.record(.wake, milliseconds: 250, tags: .init(engine: "webkit", slept: true, historyRestored: true))
        ledger.count(.typedTextSlept, by: 0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        Ledger.write(try XCTUnwrap(ledger.encoded()), in: directory)
        XCTAssertEqual(Ledger.read(in: directory), ledger)
        XCTAssertEqual(Ledger.read(in: directory.appendingPathComponent("missing")), Ledger())

        let file = directory.appendingPathComponent(Ledger.fileName)
        try Data(#"{"version":99,"moments":{}}"#.utf8).write(to: file)
        XCTAssertEqual(Ledger.read(in: directory), Ledger(), "Another version is not read as this one.")
        let text = String(decoding: try XCTUnwrap(ledger.encoded()), as: UTF8.self)
        XCTAssertFalse(text.contains("http"), "A sample holds durations and tags only.")
    }

    func testARelaunchCountsTheTabsItDidNotBringBackWhereTheyWere() throws {
        let work = UUID()
        let home = UUID()
        let tabs = (0..<5).map { _ in UUID() }
        let saved = BrowserSessionShape(spaces: [
            .init(id: work, tabs: [tabs[0], tabs[1], tabs[2]]), .init(id: home, tabs: [tabs[3]]),
        ])
        XCTAssertEqual(saved.differences(from: saved), 0)
        let missing = BrowserSessionShape(spaces: [
            .init(id: work, tabs: [tabs[0], tabs[2]]), .init(id: home, tabs: [tabs[3]]),
        ])
        XCTAssertEqual(missing.differences(from: saved), 1, "A tab gone is one difference, not one per tab after it.")
        let reordered = BrowserSessionShape(spaces: [
            .init(id: work, tabs: [tabs[1], tabs[0], tabs[2]]), .init(id: home, tabs: [tabs[3]]),
        ])
        XCTAssertEqual(reordered.differences(from: saved), 2)
        let moved = BrowserSessionShape(spaces: [
            .init(id: work, tabs: [tabs[0], tabs[1]]), .init(id: home, tabs: [tabs[3], tabs[2], tabs[4]]),
        ])
        XCTAssertEqual(moved.differences(from: saved), 2, "A tab in another Space and a tab added.")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(BrowserSessionShape.read(in: directory))
        saved.write(in: directory)
        XCTAssertEqual(BrowserSessionShape.read(in: directory), saved)
    }

    func testARelaunchSaysWhichTabsItDidNotBringBackAndHow() {
        let work = UUID()
        let home = UUID()
        let tabs = (0..<5).map { _ in UUID() }
        let saved = BrowserSessionShape(spaces: [
            .init(id: work, tabs: [tabs[0], tabs[1], tabs[2]]), .init(id: home, tabs: [tabs[3]]),
        ])
        XCTAssertEqual(saved.compared(with: saved), .init())
        let restored = BrowserSessionShape(spaces: [
            .init(id: work, tabs: [tabs[1], tabs[4]]), .init(id: home, tabs: [tabs[3], tabs[2]]),
        ])
        let found = restored.compared(with: saved)
        XCTAssertEqual(found, .init(missing: [tabs[0]], added: [tabs[4]], moved: [tabs[2]], reordered: 0))
        XCTAssertEqual(found.total, restored.differences(from: saved))
        XCTAssertEqual(
            found.line { $0 == tabs[4] ? "current Start Page" : nil },
            "The restored session differs from the last clean quit in 3 places: 1 missing, 1 added,"
                + " 1 in another Space, 0 out of order; added: current Start Page")
    }

    @MainActor
    func testABegunMomentEndsOnceAndOnlyWithinItsReach() {
        let moments = BrowserMoments()
        let start = BrowserMoments.now
        moments.begin(.commandBarReturn, at: start)
        moments.end(.commandBarReturn, at: start + 80_000_000)
        moments.end(.commandBarReturn, at: start + 90_000_000)
        XCTAssertEqual(moments.ledger.count(.commandBarReturn), 1, "A moment ends once.")
        XCTAssertEqual(moments.ledger.statistics(.commandBarReturn)?.median, 80)
        moments.begin(.commandBarReturn, at: start)
        moments.end(.commandBarReturn, at: start + 3_000_000_000, within: BrowserMoments.returnReach)
        XCTAssertEqual(
            moments.ledger.count(.commandBarReturn), 1, "A navigation long after Return did not come from it.")
        moments.end(.commandBarOpen)
        XCTAssertEqual(moments.ledger.count(.commandBarOpen), 0, "A moment never begun records nothing.")
    }

    @MainActor
    func testAHangIsTaggedWithTheMomentInFlightAndLoggedInOneLine() throws {
        let moments = BrowserMoments()
        let clock = BrowserTabSwitchClock(moments: moments)
        let start = BrowserMoments.now
        let slept = BrowserMomentLedger.Tags(engine: "chromium", slept: true)
        clock.began(arriving: NSObject(), at: start, framesPerSecond: 60, tags: slept)
        moments.recordHang(at: Date(), from: start + 100_000_000, to: start + 500_000_000)
        var hang = try XCTUnwrap(moments.ledger.moments["hang"]?.recent.last)
        XCTAssertEqual(hang.milliseconds, 400, accuracy: 0.001)
        XCTAssertEqual(hang.tags.during, "tabSwitch", "A switch still waiting for its page's frame is in flight.")
        XCTAssertEqual(hang.tags.slept, true, "The hang carries the moment's own tags.")
        XCTAssertEqual(hang.tags.engine, "chromium")
        XCTAssertNotNil(moments.ledger.summary.moments["hang"]?.tags["during=tabSwitch"])

        moments.begin(.commandBarOpen, at: start + 600_000_000)
        moments.recordHang(at: Date(), from: start + 700_000_000, to: start + 1_000_000_000)
        hang = try XCTUnwrap(moments.ledger.moments["hang"]?.recent.last)
        XCTAssertEqual(hang.tags.during, "commandBarOpen", "The moment begun last is the one in flight.")
        XCTAssertNil(hang.tags.slept)
        XCTAssertEqual(moments.ledger.count(.hang), 2)
        XCTAssertEqual(moments.activities.map(\.kind), [.tabSwitch, .commandBarOpen], "A hang is no moment in flight.")
    }

    @MainActor
    func testAHangOutsideEveryMomentIsTaggedWithNone() throws {
        let moments = BrowserMoments()
        let start = BrowserMoments.now
        moments.record(.commandBarReturn, from: start, to: start + 10_000_000)
        moments.begin(.commandBarOpen, at: start + 2_000_000_000)
        let late = start + BrowserMoments.flightReach + 1_000_000_000
        XCTAssertNil(moments.moment(inFlightFrom: start + 20_000_000, to: start + 300_000_000), "Over before it.")
        XCTAssertEqual(
            moments.moment(inFlightFrom: start + 1_000_000_000, to: start + 2_500_000_000)?.kind, .commandBarOpen)
        XCTAssertNil(
            moments.moment(inFlightFrom: late + 2_000_000_000, to: late + 2_400_000_000), "Never ended, long ago.")
        moments.recordHang(at: Date(), from: start + 20_000_000, to: start + 300_000_000)
        let hang = try XCTUnwrap(moments.ledger.moments["hang"]?.recent.last)
        XCTAssertEqual(hang.tags, BrowserMomentLedger.Tags())
        moments.end(.commandBarOpen, at: start + 2_100_000_000)
        XCTAssertEqual(moments.activities.last?.ended, start + 2_100_000_000, "Ending a moment closes its flight.")
        XCTAssertNil(moments.moment(inFlightFrom: start + 2_200_000_000, to: start + 2_600_000_000))
    }

    @MainActor
    func testAHangLineNamesWhenItBeganHowLongItLastedAndWhatWasInFlight() throws {
        let began = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-11-10T11:23:45.125Z")
        var tags = BrowserMomentLedger.Tags(engine: "chromium", slept: true)
        tags.during = "tabSwitch"
        XCTAssertEqual(
            BrowserMoments.hangLine(at: began, milliseconds: 402.4, tags: tags),
            "The main thread hung for 402 ms from 2026-11-10T11:23:45.125Z during tabSwitch"
                + " (engine=chromium, slept=true)")
        XCTAssertEqual(
            BrowserMoments.hangLine(at: began, milliseconds: 677.5, tags: .init()),
            "The main thread hung for 678 ms from 2026-11-10T11:23:45.125Z with no moment in flight")
    }

    @MainActor
    func testTheCommandBarOpenIsTimedToTheFrameThatShowsItsField() {
        BrowserMoments.shared.reset()
        defer { BrowserMoments.shared.reset() }
        BrowserChromeState().presentCommandPalette()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80), styleMask: [.borderless], backing: .buffered,
            defer: true)
        window.contentView?.addSubview(BrowserPlatformCommandPaletteField.Field())
        XCTAssertEqual(BrowserMoments.shared.ledger.count(.commandBarOpen), 0, "The frame is not committed yet.")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(BrowserMoments.shared.ledger.count(.commandBarOpen), 1)
    }

    @MainActor
    func testAMomentStartsAtTheInputThatAskedForItWhenThatInputIsRecent() throws {
        let now: UInt64 = 1_000_000_000_000
        let press = try XCTUnwrap(Self.keyDown(at: 999.9))
        XCTAssertEqual(BrowserMoments.inputTime(press, now: now), 999_900_000_000)
        let stale = try XCTUnwrap(Self.keyDown(at: 990))
        XCTAssertEqual(BrowserMoments.inputTime(stale, now: now), now, "A key long past did not ask for this moment.")
        let ahead = try XCTUnwrap(Self.keyDown(at: 1_001))
        XCTAssertEqual(BrowserMoments.inputTime(ahead, now: now), now)
        XCTAssertEqual(BrowserMoments.inputTime(nil, now: now), now)
    }

    private static func keyDown(at timestamp: TimeInterval) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: timestamp, windowNumber: 0,
            context: nil, characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17)
    }
}
