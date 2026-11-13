import XCTest

@testable import Ode

@MainActor
final class BrowserDurableTabCloseTests: XCTestCase {
    func testStaleLockedAndOrdinaryTabsDoNotCloseOrDiscardState() throws {
        for placement: TabPlacement in [.current, .pinned, .saved] {
            let context = try makeContext(placement: placement)
            let putAway = PutAwayPages(core: context.browser.core)
            let action = BrowserDurableTabCloseAction(
                browser: context.browser, spaceAccess: BrowserSpaceAccessController())
            let original = context.browser.sessionSeed
            let stale = BrowserTabRuntimeAssignment(
                tabID: context.tab.id, spaceID: context.assignment.spaceID, profileID: UUID()
            )
            XCTAssertFalse(action.perform(stale))
            if placement == .current { XCTAssertFalse(action.perform(context.assignment)) }
            XCTAssertEqual(context.browser.sessionSeed, original)

            context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: context.assignment.spaceID)
            XCTAssertFalse(action.perform(context.assignment))
            XCTAssertTrue(putAway.pages.isEmpty)
        }
    }

    func testDeferredCloseOnlyArchivesAfterApproval() throws {
        let context = try makeContext(placement: .current)
        let gate = DeferredDismissal()
        context.browser.family.pageDismissalAuthorizer = gate
        let original = context.browser.sessionSeed
        XCTAssertFalse(context.browser.closeTab(context.tab.id))
        XCTAssertEqual(context.browser.sessionSeed, original)
        XCTAssertFalse(gate.resolve(false))
        XCTAssertEqual(context.browser.sessionSeed, original)
        XCTAssertFalse(context.browser.closeTab(context.tab.id))
        XCTAssertTrue(gate.resolve(true))
        XCTAssertFalse(context.browser.shownSpace!.tabs.contains(context.tab.id))
        XCTAssertTrue(context.browser.shownSpace!.archive.contains(tabID: context.tab.id))
    }

    func testDeferredClearDoesNotCloseTabsOpenedWhileConfirmationWasPending() throws {
        let context = try makeContext(placement: .current)
        let gate = DeferredDismissal()
        context.browser.family.pageDismissalAuthorizer = gate
        let space = try XCTUnwrap(context.browser.shownSpace)
        XCTAssertFalse(context.browser.clearCurrentTabs(matching: BrowserSpaceRuntimeAssignment(space: space)))
        let newTab = try XCTUnwrap(context.browser.openNewTab(url: URL(string: "https://example.net/new")!))
        let beforeReply = context.browser.sessionSeed
        XCTAssertFalse(gate.resolve(true))
        XCTAssertEqual(context.browser.sessionSeed, beforeReply)
        XCTAssertTrue(context.browser.shownSpace!.tabs.contains(newTab))
    }

    func testDeferredCloseRechecksTheTabAssignment() throws {
        let context = try makeContext(placement: .current)
        let gate = DeferredDismissal()
        context.browser.family.pageDismissalAuthorizer = gate
        XCTAssertFalse(context.browser.closeTab(context.tab.id))
        context.browser.family.pageDismissalAuthorizer = nil
        context.browser.deleteTab(context.tab.id, in: context.assignment.spaceID)
        let beforeReply = context.browser.sessionSeed
        XCTAssertFalse(gate.resolve(true))
        XCTAssertEqual(context.browser.sessionSeed, beforeReply)
    }

    func testDurablePageIsNotRetiredWhenCloseIsCanceled() throws {
        let context = try makeContext(placement: .saved)
        let gate = DeferredDismissal()
        context.browser.family.pageDismissalAuthorizer = gate
        let putAway = PutAwayPages(core: context.browser.core)
        let action = BrowserDurableTabCloseAction(
            browser: context.browser, spaceAccess: BrowserSpaceAccessController())
        let original = context.browser.sessionSeed
        XCTAssertFalse(action.perform(context.assignment))
        XCTAssertTrue(putAway.pages.isEmpty)
        XCTAssertFalse(gate.resolve(false))
        XCTAssertTrue(putAway.pages.isEmpty)
        XCTAssertEqual(context.browser.sessionSeed, original)
        XCTAssertFalse(action.perform(context.assignment))
        XCTAssertTrue(gate.resolve(true))
        XCTAssertEqual(putAway.pages.map(\.tabID), [context.tab.id])
    }

    /// Clear Unpinned Tabs archives the shown Space's open tabs however recently
    /// they were used, keeps its pinned and saved tabs, and leaves other Spaces
    /// alone, even a tab there past its cleanup lifetime.
    func testClearUnpinnedTabsCommandArchivesOnlyTheShownSpacesOpenTabs() throws {
        let address = try XCTUnwrap(URL(string: "https://example.com"))
        let shown = TabState.Seed(title: "Shown", url: address, placement: .current)
        let recent = TabState.Seed(title: "Recent", url: address, placement: .current)
        let pinned = TabState.Seed(title: "Pinned", url: address, placement: .pinned)
        let saved = TabState.Seed(title: "Saved", url: address, placement: .saved)
        let elsewhere = TabState.Seed(
            title: "Elsewhere", url: address, placement: .current, lastActivatedAt: .now.addingTimeInterval(-86_400))
        let space = SpaceState.Seed(
            name: "Shown", symbol: "circle", accent: .indigo, folders: [], tabs: [shown, recent, pinned, saved])
        let other = SpaceState.Seed(
            name: "Other", symbol: "circle", accent: .indigo, folders: [], tabs: [elsewhere])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space, other]), showing: space.id, tabs: [space.id: shown.id])
        let actions = BrowserCommandActions(
            browser: browser, pages: BrowserPagePool(browser: browser), chrome: BrowserChromeState(), windows: nil)

        actions.perform(.clearUnpinnedTabs)

        let cleared = try XCTUnwrap(browser.spaceModel(space.id))
        XCTAssertEqual(Set(cleared.tabs.models.map(\.id)), [pinned.id, saved.id])
        XCTAssertTrue(cleared.archive.contains(tabID: shown.id))
        XCTAssertTrue(cleared.archive.contains(tabID: recent.id))
        XCTAssertTrue(try XCTUnwrap(browser.spaceModel(other.id)).tabs.contains(elsewhere.id))
    }

    private final class DeferredDismissal: BrowserPageDismissalAuthorizing {
        var pending: (@MainActor () -> Bool)?
        func performDismissal(
            of assignments: [BrowserTabRuntimeAssignment], in browser: BrowserStore,
            operation: @escaping @MainActor () -> Bool
        ) -> Bool {
            pending = operation
            return false
        }
        func resolve(_ allowed: Bool) -> Bool {
            let operation = pending
            pending = nil
            return allowed && operation?() == true
        }
    }

    private func makeContext(placement: TabPlacement) throws -> Context {
        let root = try XCTUnwrap(URL(string: "https://example.com/root"))
        let child = try XCTUnwrap(URL(string: "https://example.com/child"))
        let tab = TabState.Seed(title: "Durable", url: child, savedURL: root, placement: placement)
        let copy = TabState.Seed(title: "Independent copy", url: child, placement: .current)
        let archived = [
            ArchivedTabState.Seed(
                tab: TabState.Seed(title: "Archive", url: child, placement: .current), archivedAt: .now,
                reason: .closed)
        ]
        let space = SpaceState.Seed(
            name: "Test", symbol: "circle", accent: .indigo,
            folders: [], tabs: [tab, copy], archivedTabs: archived
        )
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]),
            showing: space.id, tabs: [space.id: tab.id]
        )
        return Context(
            browser: browser, tab: tab, copy: copy, archived: archived,
            assignment: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
        )
    }

    private struct Context {
        let browser: BrowserStore
        let tab: TabState.Seed
        let copy: TabState.Seed
        let archived: [ArchivedTabState.Seed]
        let assignment: BrowserTabRuntimeAssignment
    }

    /// Hears each saved or pinned tab's page the core puts away.
    @MainActor
    private final class PutAwayPages {
        private(set) var pages: [TabPagePutAway] = []

        init(core: OdeCore) {
            core.followPutAwayPages(self) { [weak self] in self?.pages.append($0) }
        }
    }
}
