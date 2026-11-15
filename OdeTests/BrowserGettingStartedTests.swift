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

    func testSeededPracticeSwitchesItsOwnSpacesAndSavesWithoutTouchingTheRealSession() throws {
        let real = BrowserStore(seed: .preview)
        let original = real.sessionSeed
        let trail = TabState.Seed(
            title: PracticeTab.trail.title, url: URL(string: PracticeTab.trail.url), placement: .current)
        let work = SpaceState.Seed(name: "Work", tabs: [.startPage()])
        let personal = SpaceState.Seed(name: "Personal", tabs: [trail])
        let practice = BrowserGettingStartedPractice(spaces: [personal, work])
        XCTAssertTrue(practice.browser.workspaceModel?.kind.isPractice == true)
        XCTAssertFalse(practice.browser.core === real.core)
        practice.browser.saveTab(trail.id)
        XCTAssertEqual(practice.space.tabs.model(trail.id)?.placement, .saved)

        practice.browser.selectSpace(work.id)
        let context = try XCTUnwrap(
            practice.listContext(
                capabilities: BrowserInteractionCapabilities(
                    supportsHover: true, supportsTouch: false, pairsRowWithPromotedSurface: false)))
        XCTAssertEqual(practice.space.id, work.id)
        XCTAssertEqual(context.space.id, work.id)
        practice.browser.selectSpace(personal.id)
        XCTAssertEqual(practice.space.tabs.model(trail.id)?.placement, .saved)
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

    func testNativeGuideRunsAvailableWindowCommandsEvenWhenTheyAreAbsentFromRankedResults() {
        let browser = BrowserStore(seed: .preview)
        var performed: [ShortcutCommand] = []
        var isAvailable = true
        let commands = BrowserCommandPaletteCommandRegistry(
            commands: [], supportedCommands: [.newTab], perform: { performed.append($0) },
            canPerform: { _ in isAvailable })
        let actions = BrowserNativeTabActions(
            browser: browser, spaceAccess: BrowserSpaceAccessController(), commands: commands, didOpenURL: {})
        XCTAssertTrue(actions.runCommand(.newTab))
        XCTAssertFalse(actions.runCommand(.toggleSidebar))
        isAvailable = false
        XCTAssertFalse(actions.runCommand(.newTab))
        XCTAssertEqual(performed, [.newTab])
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

    func testGuideSearchSetupUsesTheOwnedWindowsRealSettingsRouteAndRequiresCurrentSource() throws {
        let browser = BrowserStore.preview()
        let guideID = try XCTUnwrap(browser.openGettingStarted())
        let source = try XCTUnwrap(browser.shownTabAssignment)
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let access = BrowserSpaceAccessController()
        let root = BrowserRootModel(
            browser: browser, pages: pages, chrome: BrowserChromeState(), spaceAccess: access, windowState: nil,
            startupBehavior: .lastActiveTab, persistedSidebarWidth: 260)
        let settings = BrowserSpaceSettingsPresentationState()
        let actions = BrowserNativeTabActions(
            browser: browser, spaceAccess: access,
            commands: root.paletteRegistry(
                windows: nil, layoutDirection: .leftToRight, shortcuts: nil, settings: settings),
            didOpenURL: { pages.select() })
        let before = browser.sessionSeed
        _ = BrowserSearchCatalog(core: browser.core)
        let catalog = browser.core.state.searchCatalog
        let stale = BrowserTabRuntimeAssignment(tabID: guideID, spaceID: source.spaceID, profileID: UUID())
        XCTAssertNil(actions.guideContext(stale))
        XCTAssertFalse(actions.openSearchSettings(stale))
        browser.openNewTab()
        XCTAssertNil(actions.guideContext(source))
        XCTAssertFalse(actions.openSearchSettings(source))
        browser.selectTab(guideID)
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: source.spaceID)
        XCTAssertFalse(actions.openSearchSettings(source))
        browser.unlockForTesting(try XCTUnwrap(browser.shownSpace).value.seed)
        XCTAssertNil(browser.updateSpaceAccessPolicy(.open, in: source.spaceID))
        XCTAssertEqual(settings.revision, 0)
        XCTAssertNotNil(actions.guideContext(source))
        XCTAssertTrue(actions.openSearchSettings(source))
        XCTAssertEqual((settings.request as? BrowserSettingsDestinationRequest)?.destination, .search)
        XCTAssertEqual(
            settings.requestedAssignment,
            BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID))
        XCTAssertEqual(browser.shownTab?.nativeTabContent, .settings)
        XCTAssertEqual(browser.spaceModel(source.spaceID)?.tabs.model(guideID)?.nativeTabContent, .gettingStarted)
        XCTAssertEqual(browser.windowID, root.browser.windowID)
        XCTAssertEqual(browser.core.state.searchCatalog, catalog)
        XCTAssertEqual(browser.sessionSeed.spaces.count, before.spaces.count)
        XCTAssertFalse(actions.openSearchSettings(source), "The settings tab now owns selection.")
    }

    func testBrowseDismissesOnlyTheSelectedUnlockedGuideAndKeepsItsSavedTabAndWindow() throws {
        let browser = BrowserStore.preview()
        let id = try XCTUnwrap(browser.openGettingStarted())
        let space = try XCTUnwrap(browser.shownSpace)
        let source = BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profileID)
        let windowID = browser.windowID
        var selections = 0
        let actions = BrowserNativeTabActions(
            browser: browser, spaceAccess: BrowserSpaceAccessController(), didOpenURL: { selections += 1 })

        func reject(_ assignment: BrowserTabRuntimeAssignment, content: BrowserNativeTabContent = .gettingStarted) {
            let seed = browser.sessionSeed
            let window = browser.window
            actions.dismiss(assignment, content)
            XCTAssertEqual(browser.sessionSeed, seed)
            XCTAssertEqual(browser.window, window)
            XCTAssertEqual(selections, 0)
        }

        reject(BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: UUID()))
        reject(source, content: .settings)
        browser.openNewTab()
        reject(source)
        browser.selectTab(id)
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: space.id)
        reject(source)
        browser.unlockForTesting(space.value.seed)
        XCTAssertNil(browser.updateSpaceAccessPolicy(.open, in: space.id))
        browser.replaceProfileForTesting(of: space.id, with: UUID())
        reject(source)
        browser.replaceProfileForTesting(of: space.id, with: source.profileID)
        browser.selectSpace(space.id)
        browser.selectTab(id)
        actions.dismiss(source, .gettingStarted)
        XCTAssertEqual(selections, 1)
        XCTAssertNotEqual(browser.shownTab?.id, id)
        XCTAssertEqual(browser.shownSpace?.tabs.model(id)?.nativeTabContent, .gettingStarted)
        XCTAssertEqual(browser.shownSpace?.tabs.model(id)?.placement, .saved)
        XCTAssertEqual(browser.windowID, windowID)

        browser.deleteTab(id, in: space.id)
        let seed = browser.sessionSeed
        let window = browser.window
        actions.dismiss(source, .gettingStarted)
        XCTAssertEqual(selections, 1)
        XCTAssertEqual(browser.sessionSeed, seed)
        XCTAssertEqual(browser.window, window)
    }

}
