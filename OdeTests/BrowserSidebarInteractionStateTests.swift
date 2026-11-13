import XCTest

@testable import Ode

@MainActor
final class BrowserSidebarInteractionStateTests: XCTestCase {
    func testRepeatedCompositionPreservesTheLiveInteractionObserver() throws {
        let browser = BrowserStore.privateBrowsing()
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        XCTAssertTrue(BrowserSidebarInteractionState.connected(to: browser) === interaction)
        let space = try XCTUnwrap(browser.shownSpace)
        let tab = try XCTUnwrap(browser.shownTab)
        interaction.sidebarReorderState.stage(
            item: .tab(BrowserTabDragItem(tabID: tab.id, spaceID: space.id, profileID: space.profileID)),
            section: .tabs(placement: tab.placement, folderID: nil))

        browser.resetPrivateBrowsingSession()

        XCTAssertFalse(interaction.sidebarReorderState.hasLiftInFlight)
    }

}
