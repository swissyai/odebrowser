import XCTest

@testable import Ode

final class BrowserDownloadMenuTests: XCTestCase {
    private let destinations: [BrowserUtilityDownloadDestination] = [.open, .revealInFinder, .quickLook, .copy]

    private func menu(
        _ phase: DownloadPhase, isFileMissing: Bool = false, offersMoveToTrash: Bool = true
    ) -> [[BrowserDownloadMenu.Entry]] {
        BrowserDownloadMenu(
            item: .fixture(profileID: UUID(), phase: phase), destinations: destinations,
            isFileMissing: isFileMissing, offersMoveToTrash: offersMoveToTrash
        ).groups
    }

    func testAFinishedFileGoesToEachDestinationThenLeavesTheListOrGoesToTheTrash() {
        XCTAssertEqual(
            menu(.finished),
            [[.send(.open), .send(.revealInFinder), .send(.quickLook), .send(.copy)], [.remove, .moveToTrash]])
        XCTAssertEqual(menu(.finished, offersMoveToTrash: false).last, [.remove])
    }

    func testAMovedFileOnlyLeavesTheList() {
        XCTAssertEqual(menu(.finished, isFileMissing: true), [[.remove]])
    }

    func testARunningDownloadOnlyCancels() {
        XCTAssertEqual(menu(.downloading), [[.cancel]])
        XCTAssertEqual(menu(.preparing), [[.cancel]])
        XCTAssertEqual(menu(.awaitingApproval), [[.cancel]])
    }

    func testABlockedDownloadIsAllowedOrRemoved() {
        XCTAssertEqual(menu(.blockedAutomaticDownload), [[.allow], [.remove]])
    }

    func testAStoppedDownloadOnlyLeavesTheList() {
        XCTAssertEqual(menu(.failed), [[.remove]])
        XCTAssertEqual(menu(.canceled), [[.remove]])
    }

    func testOnlyMovingToTheTrashIsDestructive() {
        let entries: [BrowserDownloadMenu.Entry] = [
            .send(.open), .pause, .resume, .cancel, .allow, .remove, .moveToTrash,
        ]
        XCTAssertEqual(entries.filter(\.isDestructive), [.moveToTrash])
    }
}
