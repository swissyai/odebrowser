import SwiftUI
import XCTest

@testable import Ode

/// With tabs on top, the bar lists a Space's tabs in the sidebar's order and
/// the sidebar never docks: it floats over the page for what only it holds.
@MainActor
final class BrowserTopTabsTests: XCTestCase {
    func testTheBarListsPinnedThenSavedThenOpenTabsInTheSidebarsOrder() throws {
        let folder = UUID()
        let group = UUID()
        let pinned = TabState.Seed(title: "Pinned", url: URL(string: "https://pinned.example"), placement: .pinned)
        let saved = TabState.Seed(title: "Saved", url: URL(string: "https://saved.example"), placement: .saved)
        let filed = TabState.Seed(
            title: "Filed", url: URL(string: "https://filed.example"), placement: .saved, folderID: folder)
        let first = TabState.Seed(title: "First", url: URL(string: "https://first.example"), placement: .current)
        let left = TabState.Seed(
            title: "Left", url: URL(string: "https://left.example"), placement: .current, splitGroupID: group)
        let right = TabState.Seed(
            title: "Right", url: URL(string: "https://right.example"), placement: .current, splitGroupID: group)
        let space = SpaceState.Seed(
            name: "Home", symbol: "house", accent: .indigo, folders: [FolderState.Seed(id: folder, title: "Plans")],
            tabs: [pinned, saved, filed, first, left, right, TabState.Seed.startPage()])
        let browser = BrowserStore(seed: SessionState.Seed(spaces: [space]))

        let items = BrowserTabStripItems(space: try XCTUnwrap(browser.spaceModel(space.id)))

        XCTAssertEqual(items.pinned.map(\.id), [pinned.id])
        XCTAssertEqual(items.saved.map(\.id), ["tab-\(saved.id.uuidString)", "folder-\(folder.uuidString)"])
        // A Split View's tabs stand side by side, and a Start Page is listed nowhere.
        XCTAssertEqual(
            items.current.map(\.id), [first, left, right].map { "tab-\($0.id.uuidString)" })
    }

    func testWithTabsOnTopTheSidebarOnlyFloatsAndUtilitiesBringItOut() {
        let chrome = BrowserChromeState(sidebarIsPresented: true)
        chrome.tabLayout = .top

        XCTAssertEqual(
            BrowserSidebarPresentation(
                columnVisibility: chrome.columnVisibility, isFloatingSidebarPresented: false, tabLayout: .top),
            .collapsed)
        chrome.toggleUtility(.downloads)
        XCTAssertTrue(chrome.isFloatingSidebarPresented)
        XCTAssertEqual(chrome.utilityPresentation.surface, .downloads)
        // The bar of tabs stays where it was: the column flag stands for it.
        XCTAssertEqual(chrome.columnVisibility, .all)
        XCTAssertEqual(
            BrowserSidebarPresentation(
                columnVisibility: chrome.columnVisibility, isFloatingSidebarPresented: true, tabLayout: .top),
            .floating)

        chrome.toggleUtility(.downloads)
        XCTAssertFalse(chrome.isFloatingSidebarPresented)
        XCTAssertNil(chrome.utilityPresentation.surface)
        XCTAssertEqual(chrome.columnVisibility, .all)
    }

    func testTheSidebarLayoutStillDocksAndALayoutNameThisBuildDoesNotKnowReadsAsTheSidebar() {
        XCTAssertEqual(
            BrowserSidebarPresentation(columnVisibility: .all, isFloatingSidebarPresented: false, tabLayout: .sidebar),
            .docked)
        XCTAssertEqual(BrowserTabLayout.named("ribbon"), .sidebar)
        XCTAssertEqual(BrowserTabLayout.named("top"), .top)
        XCTAssertEqual(BrowserLayoutDensity.named("cozy"), .comfortable)
    }
}
