import CloudKit
import WebKit
import XCTest

@testable import Ode

@MainActor
final class BrowserGettingStartedTests: XCTestCase {
    // MARK: - Actions - Ownership

    func testEmbeddedLessonsChangeOnlyTheirDisposableTabsAndResetFromRealEffects() throws {
        let real = BrowserStore(seed: .preview)
        let original = real.sessionSeed
        let practice = BrowserGettingStartedPractice()
        let mail = try XCTUnwrap(practice.tabID(.mail))
        let trail = try XCTUnwrap(practice.tabID(.trail))
        XCTAssertTrue(practice.browser.workspaceModel?.kind.isPractice == true)
        XCTAssertEqual(practice.space.tabs.model(mail)?.placement, .current)
        XCTAssertEqual(practice.space.tabs.model(trail)?.placement, .current)

        practice.browser.pinTab(mail)
        XCTAssertEqual(practice.space.tabs.model(mail)?.placement, .pinned)
        practice.browser.saveTab(trail)
        XCTAssertEqual(practice.space.tabs.model(trail)?.placement, .saved)
        XCTAssertEqual(real.sessionSeed, original)

        practice.reset()
        let freshMail = try XCTUnwrap(practice.tabID(.mail))
        let freshTrail = try XCTUnwrap(practice.tabID(.trail))
        XCTAssertEqual(practice.space.tabs.model(freshMail)?.placement, .current)
        XCTAssertEqual(practice.space.tabs.model(freshTrail)?.placement, .current)
        XCTAssertEqual(real.sessionSeed, original)
        XCTAssertTrue(real.family.isOpen)
    }

    func testNativeStateSurvivesSelectionAndEndsAtExplicitUnload() throws {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let id = try XCTUnwrap(browser.openGettingStarted())
        pages.select()
        let space = try XCTUnwrap(browser.shownSpace)
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profileID)
        let runtime = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        let state = runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }
        state.chapter = .splitView
        state.practice.makeSplit()
        let members = state.practice.members.map(\.id)
        browser.openNewTab()
        pages.select()
        browser.selectTab(id)
        pages.select()
        XCTAssertTrue(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted) === runtime)
        XCTAssertEqual(state.chapter, .splitView)
        XCTAssertEqual(state.practice.members.map(\.id), members)
        XCTAssertFalse(
            pages.host.closeDurablePage(
                BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: UUID()), discardState: false))
        XCTAssertTrue(pages.nativeTabs.contains(assignment))
        XCTAssertTrue(
            BrowserDurableTabCloseAction(browser: browser, spaceAccess: BrowserSpaceAccessController()).perform(
                assignment))
        XCTAssertTrue(browser.shownSpace?.tabs.contains(id) == true)
        XCTAssertNil(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        browser.selectTab(id)
        pages.select()
        let reopened = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertFalse(reopened === runtime)
        XCTAssertEqual(reopened.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }.chapter, .moves)
    }

    func testNativeGuideReusesItsTabAndNeverAllocatesWebKit() throws {
        let browser = BrowserStore.hostingPages()
        let first = try XCTUnwrap(browser.openGettingStarted())
        XCTAssertEqual(browser.openGettingStarted(), first)
        XCTAssertEqual(browser.shownSpace?.tabs.models.filter { $0.nativeTabContent == .gettingStarted }.count, 1)
        XCTAssertNil(browser.shownTab?.address)
        XCTAssertFalse(try XCTUnwrap(browser.shownTab).isStartPage)
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        pages.select()
        XCTAssertEqual(pages.activeTabID, first)
        XCTAssertEqual(pages.presentedTabIDs, [first])
        XCTAssertNil(pages.activePage)
        XCTAssertFalse(pages.retainedTabIDs.contains(first))
        XCTAssertFalse(pages.retainedTabIDs.contains(first))
        pages.selectSpace(in: browser)
        XCTAssertEqual(browser.shownTab?.id, first)
    }

    func testNativeActionsRejectAStaleProfileAndKeepGuideWhenOpeningALink() throws {
        let browser = BrowserStore.preview()
        let id = try XCTUnwrap(browser.openGettingStarted())
        let space = try XCTUnwrap(browser.shownSpace)
        var opened = 0
        let actions = BrowserNativeTabActions(
            browser: browser, spaceAccess: BrowserSpaceAccessController(), didOpenURL: { opened += 1 })
        let url = URL(string: "https://example.com")!
        actions.openURL(
            BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: UUID()), .gettingStarted, url)
        XCTAssertEqual(opened, 0)
        actions.openURL(
            BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profileID), .gettingStarted, url
        )
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(browser.shownTab?.address, url)
        XCTAssertEqual(browser.shownSpace?.tabs.model(id)?.nativeTabContent, .gettingStarted)
    }

}
