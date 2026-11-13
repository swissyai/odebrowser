import XCTest

@testable import Ode

final class BrowserRecentDownloadsTests: XCTestCase {
    private let profileID = UUID()
    private let now = Date(timeIntervalSinceReferenceDate: 820_000_000)

    private func item(_ phase: DownloadPhase, startedMinutesAgo: Double = 1, seen: Bool = false) -> DownloadState {
        .fixture(
            profileID: profileID, createdAt: now.addingTimeInterval(-startedMinutesAgo * 60), phase: phase,
            isAcknowledged: seen)
    }

    func testRunningAndWaitingDownloadsAlwaysShow() {
        for phase in [DownloadPhase.preparing, .awaitingApproval, .downloading] {
            let running = item(phase, startedMinutesAgo: 600, seen: true)
            XCTAssertTrue(BrowserRecentDownloads.isRecent(running, endTime: nil, now: now))
        }
    }

    func testAFinishedFileShowsForAnHourAfterItFinishedUntilSeen() {
        let finished = item(.finished, startedMinutesAgo: 180)
        let finishedAt = { (minutes: Double) in self.now.addingTimeInterval(-minutes * 60) }

        XCTAssertTrue(BrowserRecentDownloads.isRecent(finished, endTime: finishedAt(5), now: now))
        XCTAssertTrue(BrowserRecentDownloads.isRecent(finished, endTime: finishedAt(60), now: now))
        XCTAssertFalse(BrowserRecentDownloads.isRecent(finished, endTime: finishedAt(61), now: now))
        // Without a known end, the start stands in for it.
        XCTAssertFalse(BrowserRecentDownloads.isRecent(finished, endTime: nil, now: now))
        XCTAssertTrue(BrowserRecentDownloads.isRecent(item(.finished), endTime: nil, now: now))

        XCTAssertFalse(BrowserRecentDownloads.isRecent(item(.finished, seen: true), endTime: finishedAt(1), now: now))
    }

    func testTroubleStaysUntilSeenAndACanceledDownloadLeaves() {
        XCTAssertTrue(BrowserRecentDownloads.isRecent(item(.failed, startedMinutesAgo: 600), endTime: nil, now: now))
        let blocked = item(.blockedAutomaticDownload, startedMinutesAgo: 600)
        XCTAssertTrue(BrowserRecentDownloads.isRecent(blocked, endTime: nil, now: now))
        XCTAssertFalse(BrowserRecentDownloads.isRecent(item(.failed, seen: true), endTime: nil, now: now))
        XCTAssertFalse(BrowserRecentDownloads.isRecent(item(.canceled), endTime: nil, now: now))
    }

    func testTheSidebarShowsTheNewestThreeAndCountsTheRest() {
        let items = [
            item(.downloading), item(.finished), item(.canceled), item(.failed), item(.finished, seen: true),
            item(.finished), item(.preparing),
        ]

        let recent = BrowserRecentDownloads(items: items, endTime: { _ in nil }, now: now)

        XCTAssertEqual(recent.shown.map(\.id), [items[0].id, items[1].id, items[3].id])
        XCTAssertEqual(recent.moreCount, 2)
        XCTAssertTrue(recent.hasEnded)
    }

    func testTheFootShowsOnlyWhileSomethingIsRecentAndTheListIsClosed() {
        let running = BrowserRecentDownloads(items: [item(.downloading)], endTime: { _ in nil }, now: now)
        let nothing = BrowserRecentDownloads(items: [item(.canceled)], endTime: { _ in nil }, now: now)

        XCTAssertTrue(BrowserRecentDownloads.isShown(running, besides: nil))
        XCTAssertTrue(BrowserRecentDownloads.isShown(running, besides: .history))
        XCTAssertFalse(BrowserRecentDownloads.isShown(running, besides: .downloads))
        XCTAssertFalse(BrowserRecentDownloads.isShown(nothing, besides: nil))
        XCTAssertFalse(running.hasEnded)
    }

    @MainActor
    func testTheCenterKnowsWhenADownloadEnded() {
        let center = BrowserDownloadCenter()
        let itemID = center.begin(profileID: profileID, filename: "Trail photo.png")
        XCTAssertNil(center.endTime(of: itemID))

        let before = Date.now
        center.send(CancelDownload(downloadID: itemID, message: "Canceled."))

        let ended = try? XCTUnwrap(center.endTime(of: itemID))
        XCTAssertGreaterThanOrEqual(ended ?? .distantPast, before)
        center.clear(itemID)
        XCTAssertNil(center.endTime(of: itemID))
    }
}
