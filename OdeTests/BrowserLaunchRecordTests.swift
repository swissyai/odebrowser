import XCTest

@testable import Ode

/// Keeps the record's file in memory and counts writes.
private final class MemoryLaunchFiles: BrowserLaunchRecordFiles, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URL: Data] = [:]
    private(set) var writes = 0

    func read(_ url: URL) throws -> Data? {
        lock.withLock { stored[url] }
    }

    func writeDurably(_ data: Data, to url: URL) throws {
        lock.withLock {
            stored[url] = data
            writes += 1
        }
    }

    func corrupt(_ url: URL) {
        lock.withLock { stored[url] = Data("{not json".utf8) }
    }
}

/// A clock the test moves by hand.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}

@MainActor
final class BrowserLaunchRecordTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/launch-record-tests", isDirectory: true)
    private var files = MemoryLaunchFiles()
    private var clock = TestClock()

    override func setUp() {
        super.setUp()
        files = MemoryLaunchFiles()
        clock = TestClock()
    }

    /// A new launch, as the shell opens one, reading what earlier launches left.
    private func launch() -> BrowserLaunchRecord {
        let clock = clock
        let record = BrowserLaunchRecord(directory: directory, files: files, now: { clock.now })
        record.begin(build: "0.9.2 (1)")
        return record
    }

    // MARK: - Warm and cold

    func testALaunchIsColdUntilOdeHasRunSinceTheMacStarted() {
        let booted = clock.now
        clock.advance(by: 60)
        XCTAssertFalse(launch().launchedEarlier(since: booted), "The first launch since the Mac started is cold.")
        clock.advance(by: 60)
        XCTAssertTrue(launch().launchedEarlier(since: booted))
        XCTAssertFalse(launch().launchedEarlier(since: clock.now + 1), "A restart makes the next launch cold again.")
    }

    // MARK: - Kill points

    func testAKillBeforeTheNativePhaseLeavesNoEntryAndNoStreak() {
        launch().finish()
        // Killed in the launcher before AppKit: the record is never opened.
        clock.advance(by: 60)
        XCTAssertEqual(launch().startupStreak, 0)
    }

    func testKillsWhileStartingEachCountAgainstTheNextLaunch() {
        // Killed while the core opened, after the engine started, and ten
        // seconds after the first window: none of them finished.
        _ = launch()
        clock.advance(by: 30)
        _ = launch()
        clock.advance(by: 30)
        let third = launch()
        XCTAssertEqual(third.startupStreak, 2)
        clock.advance(by: 10)
        // Ten seconds after the first window is still short of finishing.
        clock.advance(by: 30)
        XCTAssertEqual(launch().startupStreak, 3)
    }

    func testAKillAMinuteAfterTheFirstWindowFollowsAFinishedLaunch() {
        _ = launch()
        clock.advance(by: 30)
        let settled = launch()
        clock.advance(by: 60)
        settled.finish()
        clock.advance(by: 5)
        XCTAssertEqual(launch().startupStreak, 0)
    }

    func testACleanQuitResetsTheStreak() {
        _ = launch()
        clock.advance(by: 30)
        _ = launch()
        clock.advance(by: 30)
        let quitting = launch()
        quitting.endCleanly()
        clock.advance(by: 30)
        XCTAssertEqual(launch().startupStreak, 0)
    }

    func testLaunchesSevenHoursApartDoNotAddUp() {
        _ = launch()
        clock.advance(by: 7 * 60 * 60)
        _ = launch()
        clock.advance(by: 60)
        XCTAssertEqual(launch().startupStreak, 1)
        clock.advance(by: 7 * 60 * 60)
        XCTAssertEqual(launch().startupStreak, 0)
    }

    // MARK: - Safe mode

    func testAFinishedSafeLaunchCountsAsOneSoTheNextFailedStartAsksAgain() {
        let safe = launch()
        safe.enterSafeMode()
        safe.finish()
        clock.advance(by: 120)
        _ = launch()
        clock.advance(by: 30)
        XCTAssertEqual(launch().startupStreak, 2)
    }

    func testASafeLaunchThatDidNotFinishIsReported() {
        let safe = launch()
        safe.enterSafeMode()
        clock.advance(by: 20)
        let next = launch()
        XCTAssertTrue(next.safeModeFailed)
        XCTAssertEqual(next.startupStreak, 1)
    }

    // MARK: - File

    func testEveryChangeIsWrittenAndReadBack() throws {
        let record = launch()
        record.enterSafeMode()
        record.finish()
        record.endCleanly()
        XCTAssertEqual(files.writes, 4)
        let reread = BrowserLaunchRecord(directory: directory, files: files, now: { Date() })
        let stored = try XCTUnwrap(reread.history.launches.last)
        XCTAssertEqual(stored.build, "0.9.2 (1)")
        XCTAssertEqual(stored.outcome, .clean)
        XCTAssertTrue(stored.safeMode)
        XCTAssertNotNil(stored.finishedAt)
        XCTAssertNotNil(stored.endedAt)
    }

    func testAnUnreadableFileStartsAFreshHistory() {
        _ = launch()
        files.corrupt(directory.appendingPathComponent(BrowserLaunchRecord.fileName))
        let next = launch()
        XCTAssertEqual(next.history.launches.count, 1)
        XCTAssertEqual(next.startupStreak, 0)
    }

    func testTheHistoryKeepsItsNewestLaunches() {
        for _ in 0..<(BrowserLaunchHistory.mostKept + 5) {
            launch().endCleanly()
            clock.advance(by: 60)
        }
        XCTAssertEqual(launch().history.launches.count, BrowserLaunchHistory.mostKept)
    }

    func testTheDiskWriterReplacesTheFileWhole() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("launch-record-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = BrowserLaunchRecordDisk()
        let file = folder.appendingPathComponent(BrowserLaunchRecord.fileName)
        XCTAssertNil(try disk.read(file))
        try disk.writeDurably(Data("first".utf8), to: file)
        try disk.writeDurably(Data("second".utf8), to: file)
        XCTAssertEqual(try disk.read(file), Data("second".utf8))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(leftovers, [BrowserLaunchRecord.fileName])
    }
}
