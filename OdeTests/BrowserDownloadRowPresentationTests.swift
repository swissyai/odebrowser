import XCTest

@testable import Ode

final class BrowserDownloadRowPresentationTests: XCTestCase {
    func testAFinishedFileShowsItsSizeOnOneLine() {
        let finished = DownloadState.fixture(
            profileID: UUID(), progress: 1, phase: .finished, bytesReceived: 47_011)

        let presentation = BrowserDownloadRowPresentation.resolve(item: finished)

        XCTAssertTrue(presentation.isComplete)
        XCTAssertTrue(presentation.showsTransferMetrics)
        XCTAssertFalse(presentation.showsStatusAlongsideMetrics)
        XCTAssertEqual(presentation.completedSize, 47_011)
        XCTAssertEqual(presentation.layout(availableWidth: 240, usesAccessibilityTextSize: false), .singleLine)
    }

    func testAFinishedFileThatMovedSaysSoInsteadOfItsSize() {
        let finished = DownloadState.fixture(
            profileID: UUID(), progress: 1, phase: .finished, bytesReceived: 47_011)

        let presentation = BrowserDownloadRowPresentation.resolve(item: finished, fileIsMissing: true)

        XCTAssertFalse(presentation.showsTransferMetrics)
        XCTAssertEqual(presentation.statusText.resolvedForSearch(), String(localized: "Moved or deleted"))
        XCTAssertEqual(presentation.layout(availableWidth: 240, usesAccessibilityTextSize: false), .singleLine)
    }

    func testADownloadStillRunningIsNotComplete() {
        let running = DownloadState.fixture(
            profileID: UUID(), progress: 0.4, phase: .downloading, bytesReceived: 4_000)

        let presentation = BrowserDownloadRowPresentation.resolve(item: running)

        XCTAssertFalse(presentation.isComplete)
        XCTAssertTrue(presentation.showsTransferMetrics)
    }

    func testTimeLeftKeepsOnlyItsLargestUnit() {
        XCTAssertEqual(
            BrowserDownloadRowPresentation.timeRemaining(219),
            BrowserDownloadRowPresentation.timeRemaining(240))
        XCTAssertEqual(
            BrowserDownloadRowPresentation.timeRemaining(3_700),
            BrowserDownloadRowPresentation.timeRemaining(3_600))
    }
}
