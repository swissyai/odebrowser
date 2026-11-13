import SwiftUI
import XCTest

@testable import Ode

/// The sidebar as icons is the docked sidebar drawn narrow. History, the
/// Archive and Downloads come out in the full sidebar over the page, above the
/// column of icons, which keeps its place.
@MainActor
final class BrowserIconSidebarTests: XCTestCase {
    func testAColumnOfIconsStaysDockedAndItsFullSidebarFloatsOverIt() {
        XCTAssertEqual(
            BrowserSidebarPresentation(columnVisibility: .all, isFloatingSidebarPresented: false, sidebarStyle: .icons),
            .docked)
        XCTAssertEqual(
            BrowserSidebarPresentation(columnVisibility: .all, isFloatingSidebarPresented: true, sidebarStyle: .icons),
            .floating)
        // A full sidebar docks whatever was floating before it docked.
        XCTAssertEqual(
            BrowserSidebarPresentation(columnVisibility: .all, isFloatingSidebarPresented: true, sidebarStyle: .full),
            .docked)
        XCTAssertEqual(
            BrowserSidebarPresentation(
                columnVisibility: .detailOnly, isFloatingSidebarPresented: false, sidebarStyle: .icons),
            .collapsed)
    }

    func testUtilitiesComeOutOverAColumnOfIconsAndLeaveItDocked() {
        let chrome = BrowserChromeState(sidebarIsPresented: true)
        chrome.sidebarStyle = .icons

        chrome.toggleUtility(.history)
        XCTAssertTrue(chrome.isFloatingSidebarPresented)
        XCTAssertEqual(chrome.utilityPresentation.surface, .history)
        XCTAssertEqual(chrome.columnVisibility, .all)

        chrome.toggleUtility(.history)
        XCTAssertFalse(chrome.isFloatingSidebarPresented)
        XCTAssertEqual(chrome.columnVisibility, .all)
        XCTAssertEqual(BrowserSidebarStyle.named("narrow"), .full)
    }
}
