import Foundation
import WebKit
import XCTest

@testable import Ode

/// Pages that stop answering: when a page counts as frozen, what waiting and
/// the Mac's sleep change, the watch a window reads, a quit no frozen page can
/// hold past its limit, and the hangs the main thread's watchdog keeps.
@MainActor
final class BrowserFrozenPageTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Counting

    func testAPageIsFrozenOnlyOnceAnInteractionWentUnansweredForTenSeconds() {
        var page = BrowserPageResponsiveness()
        XCTAssertFalse(page.isFrozen(at: start))
        let question = page.interacted(at: start)
        XCTAssertNotNil(question)
        // A second interaction while the question is out asks nothing more.
        XCTAssertNil(page.interacted(at: start + 2))
        XCTAssertFalse(page.isFrozen(at: start + 9.9))
        XCTAssertTrue(page.isFrozen(at: start + 10))

        page.answered(question!)
        XCTAssertFalse(page.isFrozen(at: start + 30))
        XCTAssertNil(page.question)
    }

    func testWaitingKeepsTheOfferAwayForThirtySecondsWhileThePageStaysFrozen() {
        var page = BrowserPageResponsiveness()
        _ = page.interacted(at: start)
        XCTAssertTrue(page.isFrozen(at: start + 12))
        page.wait(at: start + 12)
        XCTAssertFalse(page.isFrozen(at: start + 41))
        XCTAssertTrue(page.isFrozen(at: start + 42))
    }

    func testNothingCountsWithinFifteenSecondsOfTheMacWakingOrWhileThePageIsAway() {
        var page = BrowserPageResponsiveness()
        _ = page.interacted(at: start)
        // The Mac slept with the question out and woke an hour later.
        let wake = start + 3600
        XCTAssertFalse(page.isFrozen(at: wake + 14, lastWake: wake))
        XCTAssertTrue(page.isFrozen(at: wake + 15, lastWake: wake))
        // A wake before the interaction leaves the count as it was.
        XCTAssertTrue(page.isFrozen(at: start + 10, lastWake: start - 60))
        XCTAssertFalse(page.isFrozen(at: start + 9, lastWake: start - 60))

        page.hidden()
        XCTAssertFalse(page.isFrozen(at: start + 100))
        // Coming back and interacting counts from then.
        XCTAssertNil(page.interacted(at: start + 100), "The first question is still out")
        XCTAssertFalse(page.isFrozen(at: start + 109))
        XCTAssertTrue(page.isFrozen(at: start + 110))
    }

    func testALateAnswerToAQuestionFromBeforeAStopChangesNothing() {
        var page = BrowserPageResponsiveness()
        let first = page.interacted(at: start)!
        page.reset()
        let second = page.interacted(at: start + 1)!
        XCTAssertNotEqual(first, second)
        page.answered(first)
        XCTAssertTrue(page.isFrozen(at: start + 11))
        page.answered(second)
        XCTAssertFalse(page.isFrozen(at: start + 11))
    }

    // MARK: - The watch a window reads

    func testTheWatchFreezesAfterTheLimitAndThawsWhenTheDocumentAnswers() async {
        let clock = WatchClock(start)
        let document = HeldDocument()
        let watch = BrowserPageResponsivenessWatch(ask: { await document.ask() }, now: { clock.now })
        watch.interacted()
        for _ in 0..<20 where !document.isAsked { await Task.yield() }
        XCTAssertTrue(document.isAsked)
        XCTAssertFalse(watch.isFrozen)
        clock.now = start + 10
        watch.refresh()
        XCTAssertTrue(watch.isFrozen)

        watch.wait()
        XCTAssertFalse(watch.isFrozen)
        clock.now = start + 41
        watch.refresh()
        XCTAssertTrue(watch.isFrozen)

        document.answer()
        for _ in 0..<20 where watch.isFrozen { await Task.yield() }
        XCTAssertFalse(watch.isFrozen)
    }

    // MARK: - A frozen WebKit page

    func testAWebKitPageBusyInAScriptNeverAnswersTheQuestion() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        webView.loadHTMLString("<p>Ode</p>", baseURL: nil)
        for _ in 0..<100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let ask: @MainActor () async -> Void = {
            _ = try? await webView.callAsyncJavaScript("return 0", arguments: [:], in: nil, contentWorld: .defaultClient)
        }
        let answered = expectation(description: "A responsive page answers")
        Task { @MainActor in
            await ask()
            answered.fulfill()
        }
        await fulfillment(of: [answered], timeout: 5)

        _ = try? await webView.evaluateJavaScript("setTimeout(() => { while (true) {} }, 0); 1")
        try await Task.sleep(for: .milliseconds(200))
        let frozen = expectation(description: "A page busy in a script never answers")
        frozen.isInverted = true
        Task { @MainActor in
            await ask()
            frozen.fulfill()
        }
        await fulfillment(of: [frozen], timeout: 2)
    }

    // MARK: - Quitting

    func testAQuitWaitsOnItsPagesAtMostThreeSecondsOutsideThePersonsPrompts() {
        var cap = BrowserQuitCap(startedAt: start)
        XCTAssertFalse(cap.isExpired(at: start + 2.9))
        cap.pause(at: start + 1)
        XCTAssertFalse(cap.isExpired(at: start + 60), "A dialog the person answers does not count")
        cap.resume(at: start + 61)
        XCTAssertFalse(cap.isExpired(at: start + 62.9))
        XCTAssertTrue(cap.isExpired(at: start + 63))
        XCTAssertFalse(BrowserQuitCap().isExpired(at: start + 100))
    }

    // MARK: - Hangs

    func testTheHangLogCountsEachDayAndKeepsLongHangsOnTheirOwn() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var log = BrowserHangLog()
        log.record(start: start, seconds: 0.1, calendar: calendar)
        XCTAssertTrue(log.days.isEmpty, "A stall under 250 ms is not a hang")
        log.record(start: start, seconds: 0.4, calendar: calendar)
        log.record(start: start + 60, seconds: 4.5, calendar: calendar)
        XCTAssertEqual(log.days.count, 1)
        XCTAssertEqual(log.days[0].count, 2)
        XCTAssertEqual(log.days[0].totalSeconds, 4.9, accuracy: 0.001)
        XCTAssertEqual(log.days[0].longestSeconds, 4.5)
        XCTAssertEqual(log.long, [BrowserHangLog.Hang(at: start + 60, seconds: 4.5)])

        for day in 1...20 { log.record(start: start + Double(day) * 86_400, seconds: 0.3, calendar: calendar) }
        XCTAssertEqual(log.days.count, BrowserHangLog.daysKept)
        for minute in 0..<60 { log.record(start: start + Double(minute) * 60, seconds: 3, calendar: calendar) }
        XCTAssertEqual(log.long.count, BrowserHangLog.longKept)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        log.write(in: directory)
        XCTAssertEqual(BrowserHangLog.read(in: directory), log)
        XCTAssertEqual(BrowserHangLog.read(in: directory.appendingPathComponent("missing")), BrowserHangLog())
    }

    func testTheWatchdogRecordsAMainThreadBlockAsAHang() async throws {
        let recorded = expectation(description: "The watchdog times a blocked main thread")
        let hangs = HangSink()
        let watchdog = BrowserMainThreadWatchdog(interval: 0.05, followsActivation: false) { _, seconds in
            hangs.add(seconds)
            if seconds >= 0.3 { recorded.fulfill() }
        }
        watchdog.start()
        try await Task.sleep(for: .milliseconds(150))
        blockMainThread(for: 0.5)
        await fulfillment(of: [recorded], timeout: 5)
        watchdog.stop()
        XCTAssertGreaterThanOrEqual(hangs.longest, 0.3)
    }
}

/// Holds the main thread, as a hang does.
@MainActor
private func blockMainThread(for seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}

@MainActor
private final class WatchClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// A document that answers only when the test says so.
@MainActor
private final class HeldDocument {
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var isAsked = false

    func ask() async {
        isAsked = true
        await withCheckedContinuation { waiting = $0 }
    }

    func answer() {
        waiting?.resume()
        waiting = nil
    }
}

private final class HangSink: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: [TimeInterval] = []

    func add(_ value: TimeInterval) { lock.withLock { seconds.append(value) } }
    var longest: TimeInterval { lock.withLock { seconds.max() ?? 0 } }
}
