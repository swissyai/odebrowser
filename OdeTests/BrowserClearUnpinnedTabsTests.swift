import XCTest

@testable import Ode

/// Command-Shift-K archives the open tabs of the Space on screen at once, as
/// Arc's did: pinned and saved tabs and other Spaces stay, and Reopen Closed
/// Tab brings them all back from the archive in their order.
@MainActor
final class BrowserClearUnpinnedTabsTests: XCTestCase {
    func testClearUnpinnedTabsArchivesTheShownSpacesOpenTabsAtOnce() throws {
        let shownID = UUID()
        let otherID = UUID()
        let pinned = Self.tab("Pinned", .pinned)
        let saved = Self.tab("Saved", .saved)
        let recent = Self.tab("Recent", .current)
        let older = Self.tab("Older", .current, activated: Date(timeIntervalSince1970: 1_600_000_000))
        let elsewhere = Self.tab("Elsewhere", .current)
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [
                SpaceState.Seed(
                    id: shownID, profileID: UUID(), name: "Shown", symbol: "house", accent: .indigo, folders: [],
                    tabs: [pinned, saved, recent, older]),
                SpaceState.Seed(
                    id: otherID, profileID: UUID(), name: "Other", symbol: "briefcase", accent: .rose, folders: [],
                    tabs: [elsewhere]),
            ]))
        browser.selectSpace(shownID)
        let actions = BrowserCommandActions(
            browser: browser, pages: BrowserPagePool(browser: browser), chrome: BrowserChromeState(), windows: nil)

        XCTAssertTrue(actions.canPerform(.clearUnpinnedTabs))
        actions.perform(.clearUnpinnedTabs)

        let shown = try XCTUnwrap(browser.spaceModel(shownID))
        XCTAssertEqual(Set(shown.tabs.models.filter { !$0.isStartPage }.map(\.id)), [pinned.id, saved.id])
        XCTAssertEqual(browser.spaceModel(otherID)?.tabs.models.map(\.id), [elsewhere.id])
        XCTAssertFalse(actions.canPerform(.clearUnpinnedTabs))

        actions.perform(.reopenClosedTab)
        let reopened = shown.tabs.models.filter { $0.placement == .current && !$0.isStartPage }.map(\.id)
        XCTAssertEqual(reopened, [recent.id, older.id])
        XCTAssertEqual(browser.selectedTabID(in: shownID), recent.id)
    }

    private static func tab(_ title: String, _ placement: TabPlacement, activated: Date = .now) -> TabState.Seed {
        TabState.Seed(
            id: UUID(), title: title, url: URL(string: "https://\(title.lowercased()).example"), placement: placement,
            lastActivatedAt: activated)
    }
}
