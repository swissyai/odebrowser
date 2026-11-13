import XCTest

@testable import Ode

final class BrowserDownloadHoverPreviewTests: XCTestCase {
    private let photo = URL(fileURLWithPath: "/tmp/Trail photo.png")
    private let report = URL(fileURLWithPath: "/tmp/Quarterly report.pdf")

    func testTheSpaceBarPreviewsTheFileThePointerMovedOnto() {
        var hover = BrowserDownloadHoverPreview()
        hover.pointerMoved(over: photo, at: 10)

        XCTAssertEqual(hover.keyPressed(at: 11, isSpace: true, isEditingText: false), photo)
    }

    func testTypingWithThePointerRestingOnARowStillTypes() {
        var hover = BrowserDownloadHoverPreview()
        hover.pointerMoved(over: photo, at: 10)
        XCTAssertNil(hover.keyPressed(at: 11, isSpace: false, isEditingText: false))

        XCTAssertNil(hover.keyPressed(at: 12, isSpace: true, isEditingText: false))

        hover.pointerMoved(over: report, at: 13)
        XCTAssertEqual(hover.keyPressed(at: 14, isSpace: true, isEditingText: false), report)
    }

    func testATextFieldWithTheKeyboardKeepsTheSpaceBar() {
        var hover = BrowserDownloadHoverPreview()
        hover.pointerMoved(over: photo, at: 10)

        XCTAssertNil(hover.keyPressed(at: 11, isSpace: true, isEditingText: true))
    }

    func testOtherKeysAndLeavingTheRowPreviewNothing() {
        var hover = BrowserDownloadHoverPreview()
        hover.pointerMoved(over: photo, at: 10)
        hover.pointerLeft(report)
        XCTAssertEqual(hover.fileURL, photo)

        hover.pointerLeft(photo)
        XCTAssertNil(hover.fileURL)
        XCTAssertNil(hover.keyPressed(at: 11, isSpace: true, isEditingText: false))
    }
}

final class BrowserMacDownloadQuickLookTests: XCTestCase {
    @MainActor
    func testThePanelIsHandedTheChosenFileAlone() {
        let quickLook = BrowserMacDownloadQuickLook()
        XCTAssertFalse(quickLook.hasPreview)
        XCTAssertEqual(quickLook.numberOfPreviewItems(in: nil), 0)

        let file = URL(fileURLWithPath: "/tmp/Trail photo.png")
        quickLook.fileURL = file

        XCTAssertTrue(quickLook.hasPreview)
        XCTAssertEqual(quickLook.numberOfPreviewItems(in: nil), 1)
        XCTAssertEqual(quickLook.previewPanel(nil, previewItemAt: 0)?.previewItemURL, file)
    }
}
