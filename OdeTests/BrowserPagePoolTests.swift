import AppKit
import WebKit
import XCTest

@testable import Ode

@MainActor
final class BrowserPagePoolTests: XCTestCase {

    func testStartPageURLActionRejectsStaleLockedAndAlreadyNavigatedSources() throws {
        let draft = TabState.Seed.startPage()
        let space = makeSpace(tabs: [draft], selectedTabID: draft.id)
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: fixtureSelections
        )
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let action = BrowserStartPageNavigationAction(
            browser: browser, pages: pages, spaceAccess: BrowserSpaceAccessController()
        )
        let url = try XCTUnwrap(URL(string: "about:blank#rejected"))
        let assignment = BrowserTabRuntimeAssignment(
            tabID: draft.id, spaceID: space.id, profileID: space.profileID
        )
        XCTAssertFalse(
            action.perform(
                BrowserTabRuntimeAssignment(tabID: draft.id, spaceID: space.id, profileID: UUID()), url: url
            ))
        XCTAssertEqual(browser.shownTab?.value.seed, draft)

        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: space.id)
        XCTAssertFalse(action.perform(assignment, url: url))
        XCTAssertEqual(browser.shownTab?.value.seed, draft)

        browser.unlockForTesting(space)
        browser.updateSpaceAccessPolicy(.open, in: space.id)
        let previousURL = try XCTUnwrap(URL(string: "about:blank#already-navigated"))
        browser.navigateSelectedTab(to: previousURL.absoluteString)
        XCTAssertFalse(action.perform(assignment, url: url))
        XCTAssertEqual(browser.shownTab?.address, previousURL)
        XCTAssertNil(pages.activePage)
    }

    func testExplicitSavedLocationResetKeepsItsPageAndHistoryButRemovesOldArchive() async throws {
        let archive = try makeTabStateArchive()
        let root = try XCTUnwrap(URL(string: "https://state.crest.test/root"))
        let child = try XCTUnwrap(URL(string: "https://state.crest.test/child"))
        let tab = TabState.Seed(title: "Saved", url: nil, savedURL: root, placement: .saved)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: fixtureSelections
        )
        let pool = BrowserPagePool(
            browser: browser, usesEphemeralWebsiteDataStores: false, tabStateArchive: archive)
        defer { pool.reconcile(validTabIDs: []) }
        pool.select()
        let page = try XCTUnwrap(pool.activePage)
        try await load(root, in: page)
        try await load(child, in: page)
        browser.navigateSelectedTab(to: child.absoluteString)
        pool.archiveResidentTabStates()
        XCTAssertNotNil(archive.archivedState(profileID: space.profileID, tabID: tab.id))
        let action = BrowserSavedLocationRestoreAction(
            browser: browser, pages: pool, spaceAccess: BrowserSpaceAccessController()
        )

        let assignment = BrowserTabRuntimeAssignment(
            tabID: tab.id, spaceID: space.id, profileID: space.profileID)
        let diagnoses = ProcessInfo.processInfo.environment["ODE_NATIVE_CI_DIAGNOSTICS"] == "1"
        if diagnoses {
            let unlocked = browser.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID),
                accessController: action.spaceAccess)
            print(
                "ODE_NATIVE_CI reset phase=before childAccepted=\(browser.shownTab?.address == child) "
                    + "selectedMatches=\(browser.shownTab?.id == tab.id) unlockedMatches=\(unlocked != nil) "
                    + "shownMatches=\(unlocked?.shownTab(tab.id) != nil) "
                    + "residentMatches=\(pool.containsResidentPage(matching: assignment)) "
                    + "residentExists=\(pool.containsResidentPage(for: tab.id)) "
                    + "away=\(browser.shownTab?.isAwayFromSavedAddress == true) "
                    + "available=\(browser.returnsToSavedAddress(tab.id, in: space.id)) "
                    + "committed=\(page.committedNavigationCount) completed=\(page.completedNavigationCount)")
        }
        let performed = action.perform(assignment)
        XCTAssertTrue(performed)
        if diagnoses {
            print(
                "ODE_NATIVE_CI reset phase=after performed=\(performed) "
                    + "samePage=\(pool.activePage === page) pendingRoot=\(page.live.pendingNavigationURL == root) "
                    + "archivePresent=\(archive.archivedState(profileID: space.profileID, tabID: tab.id) != nil) "
                    + "committed=\(page.committedNavigationCount) completed=\(page.completedNavigationCount)")
        }

        XCTAssertTrue(pool.activePage === page)
        XCTAssertEqual(page.live.pendingNavigationURL, root)
        XCTAssertEqual(browser.shownTab?.id, tab.id)
        XCTAssertFalse(try XCTUnwrap(browser.shownTab).isAwayFromSavedAddress)
        XCTAssertNil(archive.archivedState(profileID: space.profileID, tabID: tab.id))
        try await load(root, in: page)
        XCTAssertTrue(page.webView.backForwardList.backList.contains { $0.url == child })
    }

    func testCompletedBackgroundNavigationUpdatesItsOwnTabAndHistory() async throws {
        let context = try makeModifiedLinkContext()
        let destinationURL = try XCTUnwrap(
            URL(string: "https://background.crest.test/completed")
        )
        context.open(destinationURL, selecting: false)
        let backgroundTab = try XCTUnwrap(context.openedTabs.first)
        let webView = try XCTUnwrap(
            context.pool.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: backgroundTab.id, spaceID: context.spaceID,
                    profileID: try XCTUnwrap(context.store.spaceModel(context.spaceID)).profileID))?.webView
        )

        webView.loadSimulatedRequest(
            URLRequest(url: destinationURL),
            responseHTML: "<html><head><title>Background Ready</title></head></html>"
        )
        try await waitForLoad(destinationURL, in: webView)
        for attempt in 0..<200 {
            let tab = context.store.shownSpace?.tabs.model(backgroundTab.id)
            if tab?.title == "Background Ready",
                context.store.shownSpace?.history.entries.last?.url == destinationURL.absoluteString
            {
                break
            }
            if attempt < 199 { try await Task.sleep(for: .milliseconds(20)) }
        }

        let updatedTab = try XCTUnwrap(
            context.store.shownSpace?.tabs.model(backgroundTab.id)
        )
        XCTAssertEqual(updatedTab.title, "Background Ready")
        XCTAssertEqual(context.store.shownSpace?.history.entries.last?.url, destinationURL.absoluteString)
        XCTAssertEqual(context.store.shownTab?.id, context.sourceTabID)
        XCTAssertEqual(context.pool.activeTabID, context.sourceTabID)
    }

    func testBackgroundNavigationFailureUpdatesOnlyItsOwningTab() async throws {
        let context = try makeModifiedLinkContext()
        let initialURL = try XCTUnwrap(URL(string: "about:blank#before-failure"))
        context.open(initialURL, selecting: false)
        let backgroundTab = try XCTUnwrap(context.openedTabs.first)
        let webView = try XCTUnwrap(
            context.pool.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: backgroundTab.id, spaceID: context.spaceID,
                    profileID: try XCTUnwrap(context.store.spaceModel(context.spaceID)).profileID))?.webView
        )
        try await waitForLoad(initialURL, in: webView)
        let page = try XCTUnwrap(webView.navigationDelegate as? BrowserPage)
        for _ in 0..<200 where page.completedNavigationCount == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(page.completedNavigationCount, 0, "The accepted document must finish before the failure.")
        let acceptedAddress =
            try await webView.evaluateJavaScript(
                "document.title = 'Accepted background document'; location.href") as? String
        XCTAssertEqual(acceptedAddress, initialURL.absoluteString)
        for _ in 0..<200 where page.live.title != "Accepted background document" {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(page.live.title, "Accepted background document")
        let acceptedTab = try XCTUnwrap(context.store.shownSpace?.tabs.model(backgroundTab.id)).value
        let acceptedHistory = context.store.shownSpace?.history.entries
        XCTAssertEqual(acceptedTab.url, initialURL.absoluteString)
        // A loopback peer closes every connection, so this exercises native
        // failure delivery without DNS, unsafe ports or an assumed free port.
        let server = try BrowserPrivacyHTTPServer(refusesConnections: true)
        try await server.start()
        defer { server.stop() }
        let failureURL = try XCTUnwrap(URL(string: "https://127.0.0.1:\(server.port)/unreachable"))

        page.load(failureURL)
        try await waitUntil("a navigation failure", timeout: .seconds(4), interval: .milliseconds(20)) {
            page.live.failure != nil
        }

        let failedTab = try XCTUnwrap(
            context.store.shownSpace?.tabs.model(backgroundTab.id)
        )
        XCTAssertEqual(page.live.displayURL, failureURL)
        XCTAssertEqual(failedTab.url, acceptedTab.url)
        XCTAssertEqual(failedTab.title, acceptedTab.title)
        XCTAssertEqual(context.store.shownSpace?.history.entries, acceptedHistory)
        XCTAssertEqual(context.store.shownTab?.id, context.sourceTabID)
        XCTAssertEqual(context.pool.activeTabID, context.sourceTabID)
    }

    func testBackgroundWebContentProcessRecoveryRemainsAssignedToItsTab()
        async throws
    {
        let context = try makeModifiedLinkContext()
        let destinationURL = try XCTUnwrap(
            URL(string: "about:blank#background-process-recovery")
        )
        context.open(destinationURL, selecting: false)
        let backgroundTab = try XCTUnwrap(context.openedTabs.first)
        let webView = try XCTUnwrap(
            context.pool.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: backgroundTab.id, spaceID: context.spaceID,
                    profileID: try XCTUnwrap(context.store.spaceModel(context.spaceID)).profileID))?.webView
        )
        try await waitForLoad(destinationURL, in: webView)
        let page = try XCTUnwrap(webView.navigationDelegate as? BrowserPage)

        page.webViewWebContentProcessDidTerminate(webView)

        XCTAssertTrue(context.pool.containsResidentPage(for: backgroundTab.id))
        XCTAssertEqual(context.store.shownTab?.id, context.sourceTabID)
        XCTAssertEqual(context.pool.activeTabID, context.sourceTabID)
    }

    func testCredentialAccessReconcilesAcrossAnExistingSpacePage() throws {
        let browser = BrowserStore.hostingPages(.preview)
        let pool = BrowserPagePool(browser: browser)
        pool.select()
        XCTAssertTrue(try XCTUnwrap(pool.activePage).isCredentialAccessEnabled)

        let space = try XCTUnwrap(browser.shownSpace)
        browser.updateCredentialPreferences(
            CredentialPreferences(
                isEnabled: false, syncsOdePasswordsWithICloud: false, alsoOffersSaveToSystemPasswords: false),
            in: space.id)
        pool.reconcileCredentialAccess()

        XCTAssertFalse(try XCTUnwrap(pool.activePage).isCredentialAccessEnabled)
    }

    func testSpaceSwitchingKeepsPagesResidentUntilTheProtectedSpaceRelocks() throws {
        let firstTab = TabState.Seed(title: "First", url: nil, placement: .current)
        let secondTab = TabState.Seed(title: "Second", url: nil, placement: .current)
        let firstSpace = makeSpace(tabs: [firstTab], selectedTabID: firstTab.id)
        let secondSpace = makeSpace(tabs: [secondTab], selectedTabID: secondTab.id)
        let pool = BrowserPagePool(browser: hosting(firstSpace, secondSpace))

        present(pool, showing: firstSpace.id)
        let firstPage = try XCTUnwrap(pool.activePage)
        present(pool, showing: secondSpace.id)

        XCTAssertTrue(pool.containsResidentPage(for: firstTab.id))
        XCTAssertTrue(pool.containsResidentPage(for: secondTab.id))

        let firstAssignment = BrowserTabRuntimeAssignment(
            tabID: firstTab.id, spaceID: firstSpace.id, profileID: firstSpace.profileID
        )
        XCTAssertTrue(try XCTUnwrap(pool.residentPage(matching: firstAssignment)) === firstPage)
        XCTAssertNil(
            pool.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: firstTab.id, spaceID: secondSpace.id, profileID: firstSpace.profileID
                ))
        )
        XCTAssertNil(
            pool.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: firstTab.id, spaceID: firstSpace.id, profileID: UUID()
                ))
        )
        XCTAssertEqual(pool.activeTabID, secondTab.id)

        present(pool, showing: firstSpace.id)
        XCTAssertTrue(try XCTUnwrap(pool.activePage) === firstPage)

        pool.unloadPages(in: firstSpace.id)

        XCTAssertFalse(pool.containsResidentPage(for: firstTab.id))
        XCTAssertTrue(pool.containsResidentPage(for: secondTab.id))
    }

    func testReconcileReleasesClosedTabsAndClearsAClosedSelection() {
        let first = TabState.Seed(title: "First", url: nil, placement: .current)
        let second = TabState.Seed(title: "Second", url: nil, placement: .current)
        let space = makeSpace(tabs: [first, second], selectedTabID: first.id)
        let pool = BrowserPagePool(browser: hosting(space))

        present(pool, tab: first.id, in: space.id)
        present(pool, tab: second.id, in: space.id)
        pool.reconcile(validTabIDs: [first.id])

        XCTAssertEqual(pool.retainedTabIDs, [first.id])
        XCTAssertNil(pool.activeTabID)
        XCTAssertNil(pool.activePage)
    }

    func testMemoryPressureReleasesTransientLeasesBeforeActiveTabPages() throws {
        let tab = TabState.Seed(title: "Tab", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool(browser: hosting(space))
        let url = try XCTUnwrap(URL(string: "about:blank"))

        present(pool, tab: tab.id, in: space.id)
        let inactiveLease = try XCTUnwrap(
            pool.makeTransientPageLease(url: url, in: try XCTUnwrap(pool.browser.spaceModel(space.id)))
        )
        inactiveLease.setActive(false)
        let activeLease = try XCTUnwrap(
            pool.makeTransientPageLease(url: url, in: try XCTUnwrap(pool.browser.spaceModel(space.id)))
        )

        pool.relieveMemoryPressure(.warning)
        XCTAssertNotNil(inactiveLease.page, "Unknown draft state cannot authorize a pressure discard.")
        inactiveLease.page?.receiveTypedTextMessage(false, isMainFrame: true)
        activeLease.page?.receiveTypedTextMessage(false, isMainFrame: true)
        XCTAssertEqual(pool.retainedTransientPageCount, 2)
        pool.relieveMemoryPressure(.warning)

        XCTAssertNil(inactiveLease.page)
        XCTAssertTrue(inactiveLease.wasReleasedForMemoryPressure)
        XCTAssertNotNil(activeLease.page)
        XCTAssertNotNil(pool.activePage)
        XCTAssertEqual(pool.retainedTransientPageCount, 1)

        pool.relieveMemoryPressure(.critical)

        XCTAssertNil(activeLease.page)
        XCTAssertTrue(activeLease.wasReleasedForMemoryPressure)
        XCTAssertNotNil(pool.activePage)
        XCTAssertEqual(pool.retainedTransientPageCount, 0)

        inactiveLease.restore()
        XCTAssertNotNil(inactiveLease.page)
        XCTAssertFalse(inactiveLease.wasReleasedForMemoryPressure)
    }

    /// A hidden tab whose page holds text the person typed keeps its page
    /// however long it stays hidden, while a tab hidden as long without a
    /// draft sleeps.
    func testATabHoldingTypedTextNeverSleeps() async throws {
        let tabs = ["Drafting", "Idle", "Second", "Third", "Fourth", "Shown"].map {
            TabState.Seed(title: $0, url: nil, placement: .current)
        }
        let space = makeSpace(tabs: tabs, selectedTabID: tabs[0].id)
        let pool = BrowserPagePool(browser: hosting(space))
        defer { pool.reconcile(validTabIDs: []) }
        var pages: [UUID: BrowserPage] = [:]
        for tab in tabs {
            present(pool, tab: tab.id, in: space.id)
            let page = try XCTUnwrap(pool.activePage)
            try await load(try XCTUnwrap(URL(string: "https://sleep.crest.test/\(tab.title.lowercased())")), in: page)
            pages[tab.id] = page
        }
        try XCTUnwrap(pages[tabs[0].id]).receiveTypedTextMessage(true, isMainFrame: true)

        BrowserMoments.shared.reset()
        defer { BrowserMoments.shared.reset() }
        pool.sleepUnshownTabs(at: Date().addingTimeInterval(3_600), stored: 5, protectingRecent: 0)

        XCTAssertTrue(pool.containsResidentPage(for: tabs[0].id), "A draft keeps its page.")
        XCTAssertEqual(
            BrowserMoments.shared.ledger.summary.moments[BrowserMomentLedger.Kind.wake.rawValue]?.counters,
            ["typedTextSlept": 0], "Each tab put to sleep is checked for typed text, and none held any.")
        XCTAssertFalse(pool.containsResidentPage(for: tabs[1].id), "The tab hidden longest without one sleeps.")
        XCTAssertTrue(pool.containsResidentPage(for: tabs[5].id))
    }

    func testATabSwitchIsTimedUntilTheArrivingPageReportsItsFrame() async throws {
        // The tab never loaded has an address of this Mac, so its first load
        // stays off the network.
        let tabs = [
            TabState.Seed(title: "Left", url: nil, placement: .current),
            TabState.Seed(title: "Right", url: try XCTUnwrap(URL(string: "about:blank")), placement: .current),
        ]
        let space = makeSpace(tabs: tabs, selectedTabID: tabs[0].id)
        let pool = BrowserPagePool(browser: hosting(space), browsingMode: .privateBrowsing)
        defer { pool.reconcile(validTabIDs: []) }
        present(pool, tab: tabs[0].id, in: space.id)
        let left = try XCTUnwrap(pool.activePage)
        let leftURL = try XCTUnwrap(URL(string: "https://switch.crest.test/left"))
        try await load(leftURL, in: left)
        BrowserMoments.shared.reset()

        present(pool, tab: tabs[1].id, in: space.id)
        let right = try XCTUnwrap(pool.activePage)
        let rightURL = try XCTUnwrap(URL(string: "https://switch.crest.test/right"))
        try await load(rightURL, in: right)
        left.receivePaintMessage(["url": leftURL.absoluteString, "background": "rgb(1, 2, 3)"])
        XCTAssertEqual(BrowserMoments.shared.ledger.count(.tabSwitch), 0, "The departing page ends nothing.")
        right.receivePaintMessage(["url": rightURL.absoluteString, "background": "rgb(1, 2, 3)"])
        present(pool, tab: tabs[0].id, in: space.id)
        left.receivePaintMessage(["url": leftURL.absoluteString, "background": "rgb(1, 2, 3)"])

        let recent = BrowserMoments.shared.ledger.moments[BrowserMomentLedger.Kind.tabSwitch.rawValue]?.recent ?? []
        XCTAssertEqual(
            recent.map(\.tags),
            [
                .init(engine: "webkit", slept: true, local: true, historyRestored: false),
                .init(engine: "webkit", slept: false, local: false),
            ],
            "A tab never loaded wakes as it is shown; the tab shown before comes back loaded, from the network.")
        XCTAssertEqual(BrowserMoments.shared.ledger.value(.undrawn), 0)
        let wakes = BrowserMoments.shared.ledger.moments[BrowserMomentLedger.Kind.wake.rawValue]?.recent ?? []
        XCTAssertEqual(
            wakes.map(\.tags), [.init(engine: "webkit", slept: true, local: true, historyRestored: false)],
            "The switch to the tab never loaded is its wake, loaded afresh with no kept history.")
        BrowserMoments.shared.reset()
    }

    func testReturnInTheCommandBarIsTimedToTheNavigationItStarts() async throws {
        let tab = TabState.Seed(title: "Return", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool(browser: hosting(space), browsingMode: .privateBrowsing)
        defer { pool.reconcile(validTabIDs: []) }
        present(pool, tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        BrowserMoments.shared.reset()
        defer { BrowserMoments.shared.reset() }

        BrowserMoments.shared.begin(.commandBarReturn)
        BrowserPageNavigationStarted().apply(to: page)
        XCTAssertEqual(BrowserMoments.shared.ledger.count(.commandBarReturn), 1)
        BrowserMoments.shared.begin(.commandBarReturn)
        try await load(try XCTUnwrap(URL(string: "https://return.crest.test/")), in: page)
        XCTAssertEqual(
            BrowserMoments.shared.ledger.count(.commandBarReturn), 2, "WebKit's navigation start ends it too.")
    }

    func testADownloadThatStartsWithNoFeedbackIsCounted() throws {
        let tab = TabState.Seed(title: "Download", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool(browser: hosting(space), browsingMode: .privateBrowsing)
        defer { pool.reconcile(validTabIDs: []) }
        present(pool, tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        BrowserMoments.shared.reset()
        defer { BrowserMoments.shared.reset() }

        page.showDownloadStarted(DownloadStarted(downloadID: UUID(), pageID: page.corePage.id))
        XCTAssertEqual(BrowserMoments.shared.ledger.value(.feedbackSkipped), 1, "A page in no window has no source.")
        XCTAssertEqual(BrowserMoments.shared.ledger.count(.downloadFeedback), 0)
    }

    func testDraftMetadataNeedsAMainFrameReportAndCannotBeClearedByAnotherFrame() throws {
        let tab = TabState.Seed(title: "Draft", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool(browser: hosting(space), usesEphemeralWebsiteDataStores: true)
        defer { pool.reconcile(validTabIDs: []) }
        present(pool, tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)

        XCTAssertFalse(page.hasReportedTypedText)
        page.receiveTypedTextMessage(false, isMainFrame: false)
        XCTAssertFalse(page.hasReportedTypedText, "A child frame cannot establish bridge readiness.")
        page.receiveTypedTextMessage(false, isMainFrame: true)
        XCTAssertTrue(page.hasReportedTypedText)
        XCTAssertFalse(page.holdsTypedText)
        page.receiveTypedTextMessage(true, isMainFrame: false)
        page.receiveTypedTextMessage(false, isMainFrame: false)
        page.receiveTypedTextMessage(false, isMainFrame: true)
        XCTAssertTrue(page.holdsTypedText, "Startup reports cannot erase another document's draft.")
        XCTAssertTrue(BrowserTypedTextContentBridge.holdsTypedText(NSNumber(value: 0)))
        XCTAssertTrue(BrowserTypedTextContentBridge.holdsTypedText("false"))
    }

    func testMissingDraftBridgeKeepsAHiddenPageResident() throws {
        let draft = TabState.Seed(title: "Unknown draft state", url: nil, placement: .current)
        let shown = TabState.Seed(title: "Shown", url: nil, placement: .current)
        let space = makeSpace(tabs: [draft, shown], selectedTabID: draft.id)
        let pool = BrowserPagePool(browser: hosting(space), usesEphemeralWebsiteDataStores: true)
        defer { pool.reconcile(validTabIDs: []) }
        present(pool, tab: draft.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        present(pool, tab: shown.id, in: space.id)

        pool.sleepUnshownTabs(at: Date().addingTimeInterval(3_600), stored: 5, protectingRecent: 0)
        XCTAssertTrue(pool.containsResidentPage(for: draft.id), "Unknown draft state must not authorize idle unload.")

        page.receiveTypedTextMessage(false, isMainFrame: true)
        pool.sleepUnshownTabs(at: Date().addingTimeInterval(3_600), stored: 5, protectingRecent: 0)
        XCTAssertFalse(pool.containsResidentPage(for: draft.id), "A ready, unedited hidden page remains eligible.")
    }

    /// The pool hands the schedule the Spaces its window shows: a hidden tab
    /// in a Space the window does not show sleeps after half the delay, one
    /// in the shown Space waits the whole delay, and the five hidden tabs
    /// shown most recently stay loaded.
    func testATabInASpaceTheWindowDoesNotShowSleepsSoonerAndRecentTabsStay() throws {
        let parked = TabState.Seed(title: "Parked", url: nil, placement: .current)
        let hidden = TabState.Seed(title: "Hidden", url: nil, placement: .current)
        let shown = TabState.Seed(title: "Shown", url: nil, placement: .current)
        let parkedSpace = makeSpace(tabs: [parked], selectedTabID: parked.id)
        let space = makeSpace(tabs: [hidden, shown], selectedTabID: hidden.id)
        let pool = BrowserPagePool(browser: hosting(space, parkedSpace), usesEphemeralWebsiteDataStores: true)
        defer { pool.reconcile(validTabIDs: []) }
        for (tab, spaceID) in [(parked, parkedSpace.id), (hidden, space.id), (shown, space.id)] {
            present(pool, tab: tab.id, in: spaceID)
            try XCTUnwrap(pool.activePage).receiveTypedTextMessage(false, isMainFrame: true)
        }
        let now = Date()

        pool.sleepUnshownTabs(at: now.addingTimeInterval(14 * 60), stored: 15)
        XCTAssertTrue(pool.containsResidentPage(for: parked.id), "Two hidden tabs are among the five most recent.")

        pool.sleepUnshownTabs(at: now.addingTimeInterval(8 * 60), stored: 15, protectingRecent: 0)
        XCTAssertFalse(pool.containsResidentPage(for: parked.id), "The Space no window shows halves the delay.")
        XCTAssertTrue(pool.containsResidentPage(for: hidden.id), "The shown Space keeps the whole delay.")
        pool.sleepUnshownTabs(at: now.addingTimeInterval(15 * 60), stored: 15, protectingRecent: 0)
        XCTAssertFalse(pool.containsResidentPage(for: hidden.id))
        XCTAssertTrue(pool.containsResidentPage(for: shown.id))
    }

    func testNativeWhitespaceDraftSurvivesCanceledSubmitAndIdleSleepInMainAndChildFrames() async throws {
        guard !NSApp.isActive, BrowserPointerLocation.current() == BrowserPointerLocation.outsideEveryWindow else {
            XCTFail("Native input requires the isolated test host's activation and pointer protections.")
            return
        }
        let server = try BrowserPrivacyHTTPServer()
        let editor = """
            <form onsubmit='event.preventDefault()'><textarea></textarea><button>Send</button></form>
            <script>window.lastTrusted=false;addEventListener('input',e=>window.lastTrusted=e.isTrusted,true)</script>
            """
        let html = "<!doctype html><html><body>\(editor)<iframe srcdoc=\"\(editor)\"></iframe></body></html>"
        server.overrideResponse = { _ in
            ("200 OK", "Content-Type: text/html\r\nCache-Control: no-store\r\n", Data(html.utf8))
        }
        try await server.start()
        defer { server.stop() }
        let url = server.url(host: "127.0.0.1", path: "/editor")
        for scenario in [(false, false), (false, true), (true, false), (true, true)] {
            let (isTransient, inChildFrame) = scenario
            let draft = TabState.Seed(title: "Editor", url: nil, placement: .current)
            let shown = TabState.Seed(title: "Shown", url: nil, placement: .current)
            let space = makeSpace(tabs: [draft, shown], selectedTabID: draft.id)
            let pool = BrowserPagePool(browser: hosting(space), usesEphemeralWebsiteDataStores: true)
            defer { pool.reconcile(validTabIDs: []) }
            present(pool, tab: draft.id, in: space.id)
            let lease =
                isTransient
                ? pool.makeTransientPageLease(
                    url: try XCTUnwrap(URL(string: "about:blank")),
                    in: try XCTUnwrap(pool.browser.spaceModel(space.id))
                ) : nil
            defer { lease?.release() }
            let page = try XCTUnwrap(isTransient ? lease?.page : pool.activePage)
            let mount = mountForFocus(page)
            defer { mount.window.orderOut(nil) }
            guard !NSScreen.screens.contains(where: { $0.frame.intersects(mount.window.frame) }) else {
                mount.window.orderOut(nil)
                XCTFail("The isolated fixture must remain offscreen.")
                return
            }
            page.webView.load(URLRequest(url: url))
            try await waitForLoad(url, in: page.webView)
            let document = inChildFrame ? "document.querySelector('iframe').contentDocument" : "document"
            for _ in 0..<100 {
                let ready = try await page.webView.evaluateJavaScript(
                    "(() => { const d = \(document); return !!d?.querySelector('textarea'); })()")
                if ready as? Bool == true, page.hasReportedTypedText { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(page.hasReportedTypedText)
            XCTAssertFalse(page.holdsTypedText, "The fixture must start unedited before exercising native input.")
            guard !NSApp.isActive,
                BrowserPointerLocation.current() == BrowserPointerLocation.outsideEveryWindow,
                !NSScreen.screens.contains(where: { $0.frame.intersects(mount.window.frame) })
            else {
                mount.window.orderOut(nil)
                XCTFail("Fixture protection failed before native input.")
                return
            }
            _ = mount.window.makeFirstResponder(page.webView)
            _ = try await page.webView.evaluateJavaScript("\(document).querySelector('textarea').focus(); true")
            let responder = try XCTUnwrap(mount.window.firstResponder)
            let responderView = try XCTUnwrap(responder as? NSView)
            guard responderView === page.webView || responderView.isDescendant(of: page.webView) else {
                XCTFail("Native input must belong to this fixture's engine view.")
                return
            }
            if let client = responder as? NSTextInputClient {
                client.insertText("  ", replacementRange: NSRange(location: NSNotFound, length: 0))
            } else {
                let insert = NSSelectorFromString("insertText:")
                XCTAssertTrue(responder.responds(to: insert), "The fixture needs the engine's native text responder.")
                guard responder.responds(to: insert) else { return }
                responder.perform(insert, with: "  ")
            }
            for _ in 0..<100 where !page.holdsTypedText {
                try await Task.sleep(for: .milliseconds(20))
            }
            let trusted = try await page.webView.evaluateJavaScript("\(document).defaultView.lastTrusted")
            let value = try await page.webView.evaluateJavaScript("\(document).querySelector('textarea').value")
            XCTAssertEqual(trusted as? Bool, true, "Script setters are not a native-input substitute.")
            XCTAssertEqual(value as? String, "  ")
            XCTAssertTrue(page.holdsTypedText)
            _ = try await page.webView.evaluateJavaScript("\(document).querySelector('form').requestSubmit(); true")
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertTrue(page.holdsTypedText, "Canceled submission must not authorize losing the field.")

            lease?.setActive(false)
            present(pool, tab: shown.id, in: space.id)
            pool.sleepUnshownTabs(at: Date().addingTimeInterval(3_600), stored: 5, protectingRecent: 0)
            let retained =
                isTransient
                ? lease?.page
                : pool.residentPage(
                    matching: BrowserTabRuntimeAssignment(
                        tabID: draft.id, spaceID: space.id, profileID: space.profileID))
            XCTAssertTrue(retained === page)
            let kept = try await page.webView.evaluateJavaScript("\(document).querySelector('textarea').value")
            XCTAssertEqual(kept as? String, "  ")
            for level in [MemoryPressureLevel.warning, .critical] {
                lease?.setActive(level == .critical)
                _ = try pool.browser.core.send(ReportMemoryPressure(level: level))
                pool.relieveMemoryPressure(level)
                let after =
                    isTransient
                    ? lease?.page
                    : pool.residentPage(
                        matching: BrowserTabRuntimeAssignment(
                            tabID: draft.id, spaceID: space.id, profileID: space.profileID))
                XCTAssertTrue(after === page, "Pressure must not discard the edited document.")
                if after == nil {
                    if isTransient { lease?.restore() } else { present(pool, tab: draft.id, in: space.id) }
                    let restored = try XCTUnwrap(isTransient ? lease?.page : pool.activePage)
                    try await waitForLoad(url, in: restored.webView)
                    for _ in 0..<100 {
                        let ready = try await restored.webView.evaluateJavaScript(
                            "(() => { const d = \(document); return !!d?.querySelector('textarea'); })()")
                        if ready as? Bool == true { break }
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    let restoredValue = try await restored.webView.evaluateJavaScript(
                        "\(document).querySelector('textarea').value")
                    XCTAssertEqual(
                        restoredValue as? String, "  ", "Pressure must retain the actual field after reopening.")
                    if !isTransient { present(pool, tab: shown.id, in: space.id) }
                } else {
                    let afterPressure = try await page.webView.evaluateJavaScript(
                        "\(document).querySelector('textarea').value")
                    XCTAssertEqual(afterPressure as? String, "  ")
                }
            }
            guard !NSApp.isActive,
                BrowserPointerLocation.current() == BrowserPointerLocation.outsideEveryWindow,
                !NSScreen.screens.contains(where: { $0.frame.intersects(mount.window.frame) })
            else {
                mount.window.orderOut(nil)
                XCTFail("Fixture protection failed; stop before another native scenario.")
                return
            }
        }
    }

    func testUneditedLoopbackPagesRemainEligibleForMemoryPressure() async throws {
        let server = try BrowserPrivacyHTTPServer()
        server.overrideResponse = { _ in
            ("200 OK", "Content-Type: text/html\r\nCache-Control: no-store\r\n", Data("<textarea></textarea>".utf8))
        }
        try await server.start()
        defer { server.stop() }
        let url = server.url(host: "127.0.0.1", path: "/clean")
        for isTransient in [false, true] {
            let clean = TabState.Seed(title: "Clean", url: nil, placement: .current)
            let shown = TabState.Seed.startPage()
            let space = makeSpace(tabs: [clean, shown], selectedTabID: clean.id)
            let pool = BrowserPagePool(browser: hosting(space), usesEphemeralWebsiteDataStores: true)
            defer { pool.reconcile(validTabIDs: []) }
            present(pool, tab: clean.id, in: space.id)
            let lease =
                isTransient
                ? pool.makeTransientPageLease(
                    url: url, in: try XCTUnwrap(pool.browser.spaceModel(space.id))) : nil
            defer { lease?.release() }
            let page = try XCTUnwrap(isTransient ? lease?.page : pool.activePage)
            if !isTransient { page.load(url) }
            try await waitForLoad(url, in: page.webView)
            for _ in 0..<100 where !page.corePage.mayUnload {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(page.corePage.mayUnload, "The real bridge must establish that this document is unedited.")
            lease?.setActive(false)
            present(pool, tab: shown.id, in: space.id)
            _ = try pool.browser.core.send(ReportMemoryPressure(level: .warning))
            pool.relieveMemoryPressure(.warning)
            if isTransient {
                XCTAssertNil(lease?.page)
                XCTAssertTrue(lease?.wasReleasedForMemoryPressure == true)
            } else {
                XCTAssertFalse(pool.containsResidentPage(for: clean.id))
            }
        }
    }

    func testPrivateManualUnloadArchivesNothing() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let stateful = TabState.Seed(title: "Stateful", url: nil, placement: .current)
        let other = TabState.Seed(title: "Other", url: nil, placement: .current)
        let space = makeSpace(tabs: [stateful, other], selectedTabID: stateful.id)
        let pool = BrowserPagePool(
            browser: hosting(space),
            browsingMode: .privateBrowsing,
            tabStateArchive: archive
        )
        let switchTime = Date(timeIntervalSince1970: 1_000)

        present(pool, tab: stateful.id, in: space.id, at: switchTime.addingTimeInterval(-1))
        try await load(url, in: try XCTUnwrap(pool.activePage))
        present(pool, tab: other.id, in: space.id, at: switchTime)
        pool.unloadPage(for: stateful.id)
        await archive.flushPendingWrites()

        XCTAssertFalse(pool.containsResidentPage(for: stateful.id))
        XCTAssertNil(
            archive.archivedState(profileID: space.profileID, tabID: stateful.id),
            "A private page unloaded by hand must leave nothing behind."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: archive.rootDirectory.path),
            "A private pool must not create the archive during manual unloading."
        )
    }

    /// The app's memory pressure monitor reaches each pool's own relief, as
    /// every page owner it holds, so a squeeze pauses the pool's tab previews
    /// as well as releasing its pages.
    func testMemoryPressureFromTheMonitorPausesThePoolsTabPreviews() throws {
        let pool = BrowserPagePool(browser: .hostingPages(.preview))
        let monitor = BrowserMemoryPressureMonitor(core: pool.browser.core) { [pool] }
        XCTAssertNil(pool.runtimeStore.tabPreviews.pausedUntil)
        monitor.relieve(.warning)
        XCTAssertNotNil(pool.runtimeStore.tabPreviews.pausedUntil)
    }

    func testPrivatePoolReusesOneEphemeralStorePerSpaceWithoutCredentialsOrExtensions() throws {
        let firstTab = TabState.Seed.startPage()
        let secondTab = TabState.Seed.startPage()
        let firstSpace = makeSpace(tabs: [firstTab], selectedTabID: firstTab.id)
        let secondSpace = makeSpace(tabs: [secondTab], selectedTabID: secondTab.id)
        let pool = BrowserPagePool(
            browser: hosting(firstSpace, secondSpace),
            browsingMode: .privateBrowsing
        )

        present(pool, tab: firstTab.id, in: firstSpace.id)
        let firstPage = try XCTUnwrap(pool.activePage)
        let firstStore = firstPage.webView.configuration.websiteDataStore

        XCTAssertFalse(firstStore.isPersistent)
        XCTAssertNil(firstStore.identifier)
        XCTAssertTrue(firstPage.isPrivateBrowsing)
        XCTAssertNil(firstPage.webView.configuration.webExtensionController)
        // The order the page installs its scripts in is not the contract.
        XCTAssertEqual(
            firstPage.webView.configuration.userContentController.userScripts
                .map(\.source).sorted(),
            [
                BrowserPictureInPictureScript.source,
                WebKitMediaActivityBridge.source,
                BrowserLinkHoverContentBridge.source,
                BrowserLinkDragContentBridge.source,
                BrowserLinkContextContentBridge.source,
                BrowserBlockedPopupContentBridge.source,
                BrowserGeolocationContentBridge.source,
                BrowserCosmeticFilterContentBridge.source,
                BrowserPagePaintBridge.script.source,
                BrowserTypedTextContentBridge.source,
            ].sorted(),
            "Private pages allow browsing, ad blocking and paint bridges without credential or extension scripts."
        )

        present(pool, tab: secondTab.id, in: secondSpace.id)
        let secondStore = try XCTUnwrap(pool.activePage)
            .webView.configuration.websiteDataStore
        XCTAssertFalse(firstStore === secondStore)

        present(pool, tab: firstTab.id, in: firstSpace.id)
        let restoredFirstStore = try XCTUnwrap(pool.activePage)
            .webView.configuration.websiteDataStore
        XCTAssertTrue(firstStore === restoredFirstStore)
    }

    func testPrivatePaintBridgeReleasesItsCoverWithoutRememberingTheSite() async throws {
        let tab = TabState.Seed.startPage()
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool(browser: hosting(space), browsingMode: .privateBrowsing)
        defer { pool.reconcile(validTabIDs: []) }
        present(pool, tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        let url = try XCTUnwrap(URL(string: "https://private-paint.example.test/document?private#fragment"))
        try await load(url, in: page)
        // Let the automatic first-paint report and load-settle fallback finish
        // before asking the bridge itself to release a new cover.
        try await Task.sleep(for: .milliseconds(150))
        page.paintHold.hold(image: nil, color: CGColor(gray: 0, alpha: 1))
        _ = try await page.webView.callAsyncJavaScript(
            """
            globalThis.webkit.messageHandlers.odePagePaint.postMessage({
              url: location.href, background: "rgb(20, 22, 27)"
            });
            return true;
            """, arguments: [:], in: nil, contentWorld: BrowserPagePaintBridge.contentWorld)
        for _ in 0..<10 where page.paintHold.cover != nil { await Task.yield() }
        XCTAssertNil(page.paintHold.cover, "The private page's own isolated paint bridge must be delivered.")
        XCTAssertNil(BrowserSiteBackgrounds.shared.background(for: url, in: space.profileID))
        let pageWorldHandler =
            try await page.webView.evaluateJavaScript(
                "typeof globalThis.webkit?.messageHandlers?.odePagePaint") as? String
        XCTAssertEqual(pageWorldHandler, "undefined", "Page scripts cannot reach the isolated native bridge.")
    }

    func testXCTestStandardPoolNeverUsesTheInstalledWebsiteDataStore() throws {
        guard BrowserLaunchEnvironment.current.usesEphemeralProfileStorage else {
            XCTFail("The native test host must be unnamed and keep profiles in memory before creating a page.")
            return
        }
        let tab = TabState.Seed.startPage()
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool(browser: hosting(space))

        present(pool, tab: tab.id, in: space.id)
        let store = try XCTUnwrap(
            pool.activePage?.webView.configuration.websiteDataStore
        )

        XCTAssertFalse(store.isPersistent)
        XCTAssertNil(store.identifier)
    }

    func testClosingPrivatePoolReleasesEveryResidentPage() {
        let tab = TabState.Seed.startPage()
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: fixtureSelections,
            browsingMode: .privateBrowsing)
        let pool = BrowserPagePool(browser: browser, browsingMode: .privateBrowsing)
        pool.select()
        XCTAssertFalse(pool.retainedTabIDs.isEmpty)

        pool.closePrivateBrowsingSession(browser.spaceModels.map(BrowserSpaceRuntimeAssignment.init(space:)))

        XCTAssertTrue(pool.retainedTabIDs.isEmpty)
        XCTAssertNil(pool.activePage)
        XCTAssertNil(pool.activeTabID)
    }

    func testDeletingASpacesRuntimeDataPreservesAnotherSpacesPageAndPermissions() async throws {
        let deletedTab = TabState.Seed.startPage()
        let retainedTab = TabState.Seed.startPage()
        let deletedSpace = makeSpace(
            tabs: [deletedTab],
            selectedTabID: deletedTab.id
        )
        let retainedSpace = makeSpace(
            tabs: [retainedTab],
            selectedTabID: retainedTab.id
        )
        let permissionCenter = BrowserSitePermissionCenter()
        let remover = RecordingWebsiteDataStoreRemover()
        let pool = BrowserPagePool(
            browser: hosting(deletedSpace, retainedSpace, on: .hostingPages(profileStores: remover)),
            usesEphemeralWebsiteDataStores: false,
            permissionCenter: permissionCenter
        )
        let origin = SiteOrigin(
            scheme: "https",
            host: "camera.crest.test",
            port: 443
        )
        permissionCenter.setDecision(
            .grantPersistently,
            for: .camera,
            origin: origin,
            in: deletedSpace.id
        )
        permissionCenter.setDecision(
            .denyPersistently,
            for: .camera,
            origin: origin,
            in: retainedSpace.id
        )
        present(pool, tab: deletedTab.id, in: deletedSpace.id)
        present(pool, tab: retainedTab.id, in: retainedSpace.id)

        try await pool.deleteData(for: .erasing(deletedSpace))

        XCTAssertFalse(pool.retainedTabIDs.contains(deletedTab.id))
        XCTAssertTrue(pool.retainedTabIDs.contains(retainedTab.id))
        XCTAssertEqual(pool.activeTabID, retainedTab.id)
        // The core forgets the deleted Space's own choices once it removes the Space.
        XCTAssertEqual(
            permissionCenter.records(in: retainedSpace.id).map(\.decision),
            [.denyPersistently]
        )
        XCTAssertEqual(remover.removedProfileIDs, [deletedSpace.profileID])
    }

    func testAWindowReopenedUnderAClosedWindowsIdentityKeepsItsPagesAndWhatItShows() throws {
        let first = TabState.Seed(title: "First", url: URL(string: "about:blank#first"), placement: .current)
        let second = TabState.Seed(title: "Second", url: URL(string: "about:blank#second"), placement: .current)
        let space = makeSpace(tabs: [first, second], selectedTabID: first.id)
        let store = hosting(space)
        let primary = BrowserPagePool(browser: store)
        let registry = BrowserPagePoolRegistry(primary: primary)
        let spaceAccess = BrowserSpaceAccessController()
        // The first window always reopens under the same identity.
        let windowID = UUID()
        func openWindow() -> BrowserPagePool {
            let browser = store.makeWindowStore(BrowserWindowOpening(id: windowID, copying: store.windowID))
            let pages = primary.makeWindowPool(
                browser: browser, sharesRuntimes: true, transientBrowsing: BrowserTransientBrowsingCoordinator(),
                spaceAccess: spaceAccess)
            registry.register(pages, browser: browser, for: windowID)
            return pages
        }
        let closed = openWindow()
        present(closed, tab: first.id, in: space.id)
        let runtime = try XCTUnwrap(registry.runtime(for: windowID))
        XCTAssertTrue(runtime.browser === closed.browser)
        XCTAssertTrue(runtime.pages === closed)

        // The window closes as the app closes it, while a Quick Window opened
        // over it keeps its pool.
        registry.unregister(closed, for: windowID)
        closed.releaseWindowPresentation()
        closed.browser.close()
        XCTAssertNil(registry.runtime(for: windowID))
        registry.register(closed, browser: closed.browser, for: windowID)
        XCTAssertNil(registry.runtime(for: windowID), "A closed window registers no pages.")

        let reopened = openWindow()
        present(reopened, tab: second.id, in: space.id)
        XCTAssertTrue(reopened.browser.isOpen(as: windowID))
        XCTAssertFalse(
            closed.browser.isOpen(as: windowID), "Changes the core addresses to the identity are not for it.")

        // What the closed window's pool still does, presenting again or
        // tearing down late, reaches nothing of the reopened window.
        closed.select()
        closed.releaseWindowPresentation()
        registry.unregister(closed, for: windowID)
        XCTAssertTrue(registry.runtime(for: windowID)?.pages === reopened)
        XCTAssertEqual(
            primary.runtimeStore.registeredPools.filter { $0.windowID == windowID }.map(ObjectIdentifier.init),
            [ObjectIdentifier(reopened)])
        XCTAssertTrue(reopened.presentedPage(for: second.id)?.host === reopened)
        XCTAssertEqual(reopened.browser.shownTab?.id, second.id)
        XCTAssertNil(closed.browser.windowModel)
        XCTAssertEqual(closed.browser.shownTab?.id, first.id, "A closed window keeps what it showed last.")
    }

    func testPoolRoutesAcceptedHTTPAuthenticationBackToTheExactSpaceStore() async throws {
        let tab = TabState.Seed(title: "Protected", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let protectionSpace = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 443,
            protocol: "https",
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let credentialProtectionSpace = try XCTUnwrap(
            BrowserHTTPAuthenticationProtectionSpace(protectionSpace)
        )
        let storedCredential = BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: space.id,
                origin: credentialProtectionSpace.origin,
                scope: credentialProtectionSpace.credentialScope,
                username: "member"
            ),
            password: "stored-secret"
        )
        var savedRequests: [(BrowserHTTPAuthenticationSaveRequest, UUID)] = []
        let saved = expectation(description: "Accepted credential is marked used")
        let pool = BrowserPagePool(
            browser: hosting(space),
            loadHTTPAuthenticationCredential: { requestedProtectionSpace, spaceID in
                XCTAssertEqual(spaceID, space.id)
                XCTAssertEqual(requestedProtectionSpace, credentialProtectionSpace)
                return storedCredential
            },
            saveHTTPAuthenticationCredential: { request, spaceID in
                savedRequests.append((request, spaceID))
                saved.fulfill()
            }
        )
        present(pool, tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: PagePoolAuthenticationChallengeSenderStub()
        )

        let resolution = await withCheckedContinuation { continuation in
            page.webView(page.webView, didReceive: challenge) { disposition, credential in
                continuation.resume(returning: (disposition, credential))
            }
        }

        XCTAssertEqual(resolution.0, .useCredential)
        XCTAssertEqual(resolution.1?.user, "member")
        XCTAssertEqual(resolution.1?.password, "stored-secret")
        XCTAssertTrue(savedRequests.isEmpty)

        page.webView(page.webView, didFinish: nil)
        await fulfillment(of: [saved], timeout: 1)

        XCTAssertEqual(savedRequests.count, 1)
        XCTAssertEqual(savedRequests.first?.0.replacing, storedCredential.descriptor)
        XCTAssertEqual(savedRequests.first?.1, space.id)
    }

    func testAdoptedPopupInheritsTheOpenerWebsiteDataStoreAndProfile() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()

        let popupWebView = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        let popupPage = try XCTUnwrap(context.pool.activePage)
        XCTAssertTrue(
            popupWebView.configuration.websiteDataStore
                === context.opener.webView.configuration.websiteDataStore
        )
        XCTAssertEqual(popupPage.spaceID, context.opener.spaceID)
        XCTAssertEqual(popupPage.profileID, context.opener.profileID)
    }

    func testClosingAPageTheUserOpenedKeepsItsTab() throws {
        let context = try makePopupContext()
        let openerTabID = try XCTUnwrap(context.store.shownTab?.id)

        context.opener.webViewDidClose(context.opener.webView)

        XCTAssertEqual(context.store.shownTab?.id, openerTabID)
        XCTAssertTrue(
            context.store.shownSpace?.tabs.contains(openerTabID) == true
        )
    }

    func testPrivatePopupAdoptionStaysInsideThePrivatePool() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let regular = try makePopupContext()
        let privateContext = try makePopupContext(browsingMode: .privateBrowsing)

        let popupWebView = try XCTUnwrap(
            privateContext.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        XCTAssertFalse(popupWebView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(privateContext.store.shownSpace?.tabs.models.count, 2)
        XCTAssertEqual(regular.store.shownSpace?.tabs.models.count, 1)
        XCTAssertFalse(regular.pool.activePage?.wasOpenedAsPopup == true)
        XCTAssertTrue(
            privateContext.pool.activePage?.wasOpenedAsPopup == true
        )
    }

    // MARK: - Split View presented set

    func testRelockingABackgroundSpaceInvalidatesItsRememberedResponder() throws {
        let secret = TabState.Seed(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeSpace(
            tabs: [secret], selectedTabID: secret.id, accessPolicy: .deviceOwnerAuthentication
        )
        let other = TabState.Seed(title: "Other", url: nil, placement: .current)
        let otherSpace = makeSpace(tabs: [other], selectedTabID: other.id)
        let browser = hosting(protectedSpace, otherSpace)
        browser.unlockForTesting(protectedSpace)
        let pool = BrowserPagePool(browser: browser)
        present(pool, tab: secret.id, in: protectedSpace.id)
        let secretPage = try XCTUnwrap(pool.activePage)
        let mount = mountForFocus(secretPage)
        XCTAssertTrue(mount.window.makeFirstResponder(secretPage.webView))
        present(pool, tab: other.id, in: otherSpace.id)
        let otherPage = try XCTUnwrap(pool.activePage)
        otherPage.focusRestoration.remember(otherPage.webView)
        otherPage.focusRestoration.requestRestoration()

        pool.relockProtectedSpace(try XCTUnwrap(pool.browser.spaceModel(protectedSpace.id)))
        XCTAssertTrue(otherPage.focusRestoration.hasPendingRestoration)
        present(pool, tab: secret.id, in: protectedSpace.id)

        XCTAssertTrue(pool.activePage === secretPage)
        XCTAssertFalse(secretPage.focusRestoration.hasPendingRestoration)
        pool.reconcile(validTabIDs: [])
    }

    func testSpaceFocusReturnDoesNotDisplaceNativeChrome() throws {
        let first = TabState.Seed(title: "First", url: nil, placement: .current)
        let second = TabState.Seed(title: "Second", url: nil, placement: .current)
        let firstSpace = makeSpace(tabs: [first], selectedTabID: first.id)
        let secondSpace = makeSpace(tabs: [second], selectedTabID: second.id)
        let pool = BrowserPagePool(browser: hosting(firstSpace, secondSpace))
        present(pool, tab: first.id, in: firstSpace.id)
        let firstPage = try XCTUnwrap(pool.activePage)
        let mount = mountForFocus(firstPage)
        XCTAssertTrue(mount.window.makeFirstResponder(firstPage.webView))
        present(pool, tab: second.id, in: secondSpace.id)
        let field = NSTextField(string: "Browser chrome")
        mount.host.addSubview(field)
        XCTAssertTrue(mount.window.makeFirstResponder(field))
        let chromeResponder = mount.window.firstResponder

        present(pool, tab: first.id, in: firstSpace.id)

        XCTAssertTrue(firstPage.focusRestoration.hasPendingRestoration)
        XCTAssertFalse(
            firstPage.focusRestoration.restoreIfNeeded(
                in: mount.host,
                gate: .init(browserChromeOwnsFocus: false, pageChromeOwnsFocus: false),
                applicationIsActive: true,
                accessibilityOwnsFocus: false,
                menuIsTracking: false,
                windowIsKey: true
            )
        )
        XCTAssertTrue(mount.window.firstResponder === chromeResponder)
        XCTAssertFalse(firstPage.focusRestoration.hasPendingRestoration)
        pool.reconcile(validTabIDs: [])
    }

    func testSplitCardFocusReturnKeepsEveryMemberMounted() throws {
        let groupID = UUID()
        let first = TabState.Seed(
            title: "First",
            url: URL(string: "about:blank"),
            placement: .current,
            splitGroupID: groupID
        )
        let second = TabState.Seed(
            title: "Second",
            url: URL(string: "about:blank"),
            placement: .current,
            splitGroupID: groupID
        )
        let space = makeSpace(tabs: [first, second], selectedTabID: first.id)
        let pool = BrowserPagePool(browser: hosting(space))
        present(pool, tab: first.id, in: space.id)
        let firstPage = try XCTUnwrap(pool.presentedPage(for: first.id))
        let secondPage = try XCTUnwrap(pool.presentedPage(for: second.id))
        let mount = mountSplitForFocus(firstPage, secondPage)

        XCTAssertTrue(mount.window.makeFirstResponder(firstPage.webView))
        present(pool, tab: second.id, in: space.id)
        XCTAssertTrue(mount.window.makeFirstResponder(secondPage.webView))
        present(pool, tab: first.id, in: space.id)

        XCTAssertEqual(pool.presentedTabIDs, [first.id, second.id])
        XCTAssertTrue(firstPage.webView.superview === mount.firstHost)
        XCTAssertTrue(secondPage.webView.superview === mount.secondHost)
        XCTAssertTrue(firstPage.focusRestoration.hasPendingRestoration)
        XCTAssertTrue(
            firstPage.focusRestoration.restoreIfNeeded(
                in: mount.firstHost,
                gate: .init(
                    browserChromeOwnsFocus: false,
                    pageChromeOwnsFocus: false
                ),
                applicationIsActive: true,
                accessibilityOwnsFocus: false,
                menuIsTracking: false,
                windowIsKey: true
            ),
            "The focused Split View card may take native focus only from the known card it replaces."
        )
        XCTAssertTrue(mount.window.firstResponder === firstPage.webView)
        pool.reconcile(validTabIDs: [])
    }

    func testUnloadedPageNeverRestoresAResponderFromItsPriorWebView() throws {
        let first = TabState.Seed(title: "First", url: nil, placement: .current)
        let second = TabState.Seed(title: "Second", url: nil, placement: .current)
        let space = makeSpace(tabs: [first, second], selectedTabID: first.id)
        let pool = BrowserPagePool(browser: hosting(space))
        present(pool, tab: first.id, in: space.id)
        let originalPage = try XCTUnwrap(pool.activePage)
        let originalWebView = originalPage.webView
        let mount = mountForFocus(originalPage)

        XCTAssertTrue(mount.window.makeFirstResponder(originalWebView))
        present(pool, tab: second.id, in: space.id)
        pool.unloadPage(for: first.id)
        present(pool, tab: first.id, in: space.id)
        let recreatedPage = try XCTUnwrap(pool.activePage)

        XCTAssertFalse(recreatedPage === originalPage)
        XCTAssertFalse(recreatedPage.webView === originalWebView)
        XCTAssertFalse(recreatedPage.focusRestoration.hasPendingRestoration)
        pool.reconcile(validTabIDs: [])
    }

    func testNavigationAndProcessLossClearAPendingPageResponder() throws {
        let first = TabState.Seed(title: "First", url: nil, placement: .current)
        let second = TabState.Seed(title: "Second", url: nil, placement: .current)
        let space = makeSpace(tabs: [first, second], selectedTabID: first.id)
        let pool = BrowserPagePool(browser: hosting(space))
        present(pool, tab: first.id, in: space.id)
        let firstPage = try XCTUnwrap(pool.activePage)
        let mount = mountForFocus(firstPage)

        XCTAssertTrue(mount.window.makeFirstResponder(firstPage.webView))
        present(pool, tab: second.id, in: space.id)
        // The tab shown in its place takes focus, as a real switch does, so
        // the first page has a responder to restore when it comes back.
        mount.window.makeFirstResponder(nil)
        present(pool, tab: first.id, in: space.id)
        XCTAssertTrue(firstPage.focusRestoration.hasPendingRestoration)

        firstPage.webView(
            firstPage.webView,
            didStartProvisionalNavigation: nil
        )
        XCTAssertFalse(firstPage.focusRestoration.hasPendingRestoration)

        XCTAssertTrue(mount.window.makeFirstResponder(firstPage.webView))
        present(pool, tab: second.id, in: space.id)
        // The tab shown in its place takes focus, as a real switch does, so
        // the first page has a responder to restore when it comes back.
        mount.window.makeFirstResponder(nil)
        present(pool, tab: first.id, in: space.id)
        XCTAssertTrue(firstPage.focusRestoration.hasPendingRestoration)
        firstPage.webViewWebContentProcessDidTerminate(firstPage.webView)
        XCTAssertFalse(firstPage.focusRestoration.hasPendingRestoration)
        pool.reconcile(validTabIDs: [])
    }

    func testRelockingASpaceHidesEveryCardOfAnOpenSplitWithoutUnloading() throws {
        let groupID = UUID()
        let first = TabState.Seed(
            title: "First secret",
            url: URL(string: "about:blank"),
            placement: .current,
            splitGroupID: groupID
        )
        let second = TabState.Seed(
            title: "Second secret",
            url: URL(string: "about:blank"),
            placement: .current,
            splitGroupID: groupID
        )
        let protectedSpace = makeSpace(
            tabs: [first, second],
            selectedTabID: first.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = TabState.Seed(title: "Open", url: nil, placement: .current)
        let openSpace = makeSpace(tabs: [openTab], selectedTabID: openTab.id)
        let browser = hosting(openSpace, protectedSpace)
        browser.unlockForTesting(protectedSpace)
        let pool = BrowserPagePool(browser: browser)

        present(pool, tab: openTab.id, in: openSpace.id)
        present(pool, tab: first.id, in: protectedSpace.id)
        XCTAssertEqual(pool.presentedTabIDs, [first.id, second.id])

        pool.relockProtectedSpace(try XCTUnwrap(pool.browser.spaceModel(protectedSpace.id)))

        XCTAssertTrue(
            pool.presentedTabIDs.isEmpty,
            "Locking a Space must take every card away, not just the focused one."
        )
        XCTAssertNil(pool.activeTabID)
        XCTAssertTrue(pool.containsResidentPage(for: first.id))
        XCTAssertTrue(pool.containsResidentPage(for: second.id))
        XCTAssertTrue(pool.containsResidentPage(for: openTab.id))
    }

    func testSplitCopyUsesResidentChildURLAndIndependentNativeBackHistory() async throws {
        let root = try XCTUnwrap(URL(string: "https://state.crest.test/root"))
        let child = try XCTUnwrap(URL(string: "https://state.crest.test/child"))
        let source = TabState.Seed(title: "Saved", url: root, placement: .saved)
        let target = TabState.Seed(title: "Open", url: root, placement: .current)
        let space = makeSpace(tabs: [source, target], selectedTabID: source.id)
        let store = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: fixtureSelections)
        let pool = BrowserPagePool(browser: store)
        store.tabCopying = pool
        present(pool, tab: source.id, in: space.id)
        let originalPage = try XCTUnwrap(pool.activePage)
        try await load(root, in: originalPage)
        try await load(child, in: originalPage)
        store.selectTab(target.id)

        XCTAssertTrue(store.splitTabWithSelectedTab(source.id, matching: BrowserSpaceRuntimeAssignment(space: space)))
        let copy = try XCTUnwrap(store.shownTab)
        XCTAssertEqual(copy.address, child, "The copy starts where the resident page is.")
        // The saved tab stays saved, where its page's recorded navigation left it.
        XCTAssertEqual(store.shownSpace?.savedTabs.map(\.id), [source.id])
        pool.select()
        let copyPage = try XCTUnwrap(pool.activePage)
        XCTAssertFalse(copyPage === originalPage)
        XCTAssertEqual(copyPage.webView.url, child)
        XCTAssertEqual(
            copyPage.webView.backForwardList.backList.map(\.url),
            originalPage.webView.backForwardList.backList.map(\.url))
        XCTAssertTrue(copyPage.webView.canGoBack)
        XCTAssertEqual(originalPage.webView.url, child)
        pool.reconcile(validTabIDs: [])
    }

    func testManualUnloadingATabArchivesItsSessionStateAndReselectingRestoresIt() async throws {
        let archive = try makeTabStateArchive()
        let firstURL = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://state.crest.test/two"))
        let stateful = TabState.Seed(title: "Stateful", url: nil, placement: .current)
        let other = TabState.Seed(title: "Other", url: nil, placement: .current)
        let space = makeSpace(tabs: [stateful, other], selectedTabID: stateful.id)
        let pool = BrowserPagePool(
            browser: hosting(space),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        present(pool, tab: stateful.id, in: space.id)
        let originalPage = try XCTUnwrap(pool.activePage)
        try await load(firstURL, in: originalPage)
        try await load(secondURL, in: originalPage)
        XCTAssertTrue(originalPage.webView.canGoBack)

        present(pool, tab: other.id, in: space.id)
        pool.unloadPage(for: stateful.id)
        XCTAssertFalse(pool.containsResidentPage(for: stateful.id))
        await archive.flushPendingWrites()
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profileID, tabID: stateful.id)
        )

        present(pool, tab: stateful.id, in: space.id)
        let restoredPage = try XCTUnwrap(pool.activePage)

        XCTAssertFalse(restoredPage === originalPage)
        XCTAssertEqual(restoredPage.webView.url, secondURL)
        XCTAssertTrue(
            restoredPage.webView.canGoBack,
            "A restored tab must come back with the back/forward list it had."
        )
        XCTAssertEqual(
            restoredPage.webView.backForwardList.backList.map(\.url),
            [firstURL]
        )

        pool.reconcile(validTabIDs: [])
    }

    // MARK: - Archived tab state

    func testAFreshPoolOnTheSameArchiveRestoresWhatTheOldPoolLeft() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://state.crest.test/two"))
        let stateful = TabState.Seed(title: "Stateful", url: nil, placement: .current)
        let space = makeSpace(tabs: [stateful], selectedTabID: stateful.id)
        let firstBrowser = hosting(space)
        let firstLaunch = BrowserPagePool(
            browser: firstBrowser,
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        present(firstLaunch, tab: stateful.id, in: space.id)
        let page = try XCTUnwrap(firstLaunch.activePage)
        try await load(url, in: page)
        try await load(secondURL, in: page)
        // What a scene resigning active does, rather than an eviction.
        firstLaunch.archiveResidentTabStates()
        await firstLaunch.flushPendingTabStateWrites()
        let relaunched = try XCTUnwrap(firstBrowser.spaceModel(space.id)).value.seed
        firstLaunch.reconcile(validTabIDs: [])

        let secondLaunch = BrowserPagePool(
            browser: hosting(relaunched),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )
        present(secondLaunch, tab: stateful.id, in: space.id)
        let restoredPage = try XCTUnwrap(secondLaunch.activePage)

        XCTAssertEqual(restoredPage.webView.url, secondURL)
        XCTAssertEqual(
            restoredPage.webView.backForwardList.backList.map(\.url),
            [url]
        )

        secondLaunch.reconcile(validTabIDs: [])
    }

    func testClosingAResidentTabArchivesItsHistoryBeforeReconciliationReleasesIt()
        async throws
    {
        let archive = try makeTabStateArchive()
        let firstURL = try XCTUnwrap(
            URL(string: "https://state.crest.test/close-first")
        )
        let secondURL = try XCTUnwrap(
            URL(string: "https://state.crest.test/close-second")
        )
        let stateful = TabState.Seed(
            title: "Stateful",
            url: nil,
            placement: .current
        )
        let fallback = TabState.Seed(
            title: "Fallback",
            url: nil,
            placement: .current
        )
        let space = makeSpace(
            tabs: [stateful, fallback],
            selectedTabID: stateful.id
        )
        let browser = hosting(space)
        let pool = BrowserPagePool(
            browser: browser,
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        pool.select()
        let originalPage = try XCTUnwrap(pool.activePage)
        try await load(firstURL, in: originalPage)
        try await load(secondURL, in: originalPage)

        XCTAssertTrue(browser.closeTab(stateful.id))
        pool.reconcile()
        await pool.flushPendingTabStateWrites()

        XCTAssertFalse(pool.containsResidentPage(for: stateful.id))
        XCTAssertNotNil(
            archive.archivedState(
                profileID: space.profileID,
                tabID: stateful.id
            ),
            "Closing must write the resident interaction state before the session sweep releases the page."
        )

        browser.restoreArchivedTab(stateful.id)
        present(pool, tab: stateful.id, in: space.id)
        let restoredPage = try XCTUnwrap(pool.activePage)

        XCTAssertFalse(restoredPage === originalPage)
        XCTAssertEqual(restoredPage.webView.url, secondURL)
        XCTAssertEqual(
            restoredPage.webView.backForwardList.backList.map(\.url),
            [firstURL]
        )

        pool.reconcile(validTabIDs: [])
    }

    func testStateWebKitRefusesFallsBackToAnOrdinaryLoad() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = TabState.Seed(title: "Corrupt", url: url, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        // Correctly framed and stamped for this build, so only WebKit can refuse it.
        archive.archive(
            interactionState: Data((0..<1024).map { _ in UInt8.random(in: 0...255) }),
            url: url,
            history: nil,
            profileID: space.profileID,
            tabID: tab.id
        )
        await archive.flushPendingWrites()
        let pool = BrowserPagePool(
            browser: hosting(space),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        present(pool, tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)

        XCTAssertTrue(page.webView.backForwardList.backList.isEmpty)
        XCTAssertEqual(
            page.live.pendingNavigationURL ?? page.webView.url,
            url,
            "Refused state must leave a plain load of the tab's own URL behind."
        )

        pool.reconcile(validTabIDs: [])
    }

    func testPrivateBrowsingArchivesNoTabStateEvenWhenGivenAnArchive() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = TabState.Seed(title: "Private", url: nil, placement: .current)
        let other = TabState.Seed(title: "Other", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab, other], selectedTabID: tab.id)
        let pool = BrowserPagePool(
            browser: hosting(space),
            browsingMode: .privateBrowsing,
            tabStateArchive: archive
        )

        present(pool, tab: tab.id, in: space.id)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        present(pool, tab: other.id, in: space.id)
        pool.archiveResidentTabStates()
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(profileID: space.profileID, tabID: tab.id),
            "Private browsing must leave nothing on disk to restore."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: archive.rootDirectory.path),
            "A private pool must not even create the archive's directory."
        )
    }

    func testDeletingASpaceRemovesItsArchivedTabStates() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = TabState.Seed(title: "Deleted", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let survivingProfileID = UUID()
        let survivingTabID = UUID()
        archive.archive(
            interactionState: Data("other space".utf8),
            url: url,
            history: nil,
            profileID: survivingProfileID,
            tabID: survivingTabID
        )
        let pool = BrowserPagePool(
            browser: hosting(space, on: .hostingPages(profileStores: RecordingWebsiteDataStoreRemover())),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        present(pool, tab: tab.id, in: space.id)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.unloadPage(for: tab.id)
        await archive.flushPendingWrites()
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profileID, tabID: tab.id)
        )

        try await pool.deleteData(for: .erasing(space))
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(profileID: space.profileID, tabID: tab.id),
            "Deleting a Space must take its archived session state with it."
        )
        XCTAssertNotNil(
            archive.archivedState(
                profileID: survivingProfileID,
                tabID: survivingTabID
            ),
            "Space deletion must not reach another Space's state."
        )
    }

    func testRelockingAProtectedSpacePurgesTheStateItsUnloadsLeftBehind() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secret = TabState.Seed(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeSpace(
            tabs: [secret],
            selectedTabID: secret.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = TabState.Seed(title: "Open", url: nil, placement: .current)
        let openSpace = makeSpace(tabs: [openTab], selectedTabID: openTab.id)
        let browser = hosting(openSpace, protectedSpace)
        browser.unlockForTesting(protectedSpace)
        let pool = BrowserPagePool(
            browser: browser,
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        present(pool, tab: openTab.id, in: openSpace.id)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.unloadPage(for: openTab.id)
        present(pool, tab: secret.id, in: protectedSpace.id)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        // The unload that leaves the residue: the page is gone from memory
        // long before the Space relocks, and its state is already on disk.
        pool.unloadPage(for: secret.id)
        await archive.flushPendingWrites()
        XCTAssertNotNil(
            archive.archivedState(
                profileID: protectedSpace.profileID,
                tabID: secret.id
            )
        )

        pool.relockProtectedSpace(try XCTUnwrap(pool.browser.spaceModel(protectedSpace.id)))
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(
                profileID: protectedSpace.profileID,
                tabID: secret.id
            ),
            "A relocked Space must leave no page state at rest."
        )
        XCTAssertNotNil(
            archive.archivedState(
                profileID: openSpace.profileID,
                tabID: openTab.id
            ),
            "Relocking one Space must not reach another Space's state."
        )
    }

    func testRepeatedRelockingPreservesLoadedPageScrollFormsAndHistory() async throws {
        let firstURL = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://state.crest.test/two"))
        let tab = TabState.Seed(title: "Secret", url: nil, placement: .current)
        let space = makeSpace(
            tabs: [tab], selectedTabID: tab.id, accessPolicy: .deviceOwnerAuthentication
        )
        let browser = hosting(space)
        browser.unlockForTesting(space)
        let pool = BrowserPagePool(browser: browser)
        present(pool, tab: tab.id, in: space.id)
        let original = try XCTUnwrap(pool.activePage)
        try await load(firstURL, in: original)
        try await load(secondURL, in: original)
        _ = try await original.webView.evaluateJavaScript(
            "document.body.innerHTML += '<input id=note>'; document.getElementById('note').value = 'draft'; window.scrollTo(0, 850);"
        )
        let scrollValue = try await original.webView.evaluateJavaScript("window.scrollY")
        let scroll = try XCTUnwrap(scrollValue as? Double)
        XCTAssertGreaterThan(scroll, 0)

        for _ in 0..<3 {
            pool.relockProtectedSpace(try XCTUnwrap(pool.browser.spaceModel(space.id)))
            XCTAssertNil(pool.activePage)
            XCTAssertTrue(pool.presentedTabIDs.isEmpty)
            present(pool, tab: tab.id, in: space.id)
            XCTAssertTrue(pool.activePage === original)
            XCTAssertTrue(original.webView.canGoBack)
            let currentScroll = try await original.webView.evaluateJavaScript("window.scrollY")
            let draft = try await original.webView.evaluateJavaScript("document.getElementById('note').value")
            XCTAssertEqual(currentScroll as? Double, scroll)
            XCTAssertEqual(draft as? String, "draft")
        }
        pool.reconcile(validTabIDs: [])
    }

    func testRelockingAnOpenSpaceKeepsItsArchivedTabState() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = TabState.Seed(title: "Ordinary", url: nil, placement: .current)
        let openSpace = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool(
            browser: hosting(openSpace),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        present(pool, tab: tab.id, in: openSpace.id)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.unloadPage(for: tab.id)
        await archive.flushPendingWrites()

        // The lock sweep hands over every Space it walks; an unprotected one has
        // nothing to relock, so its state has to survive the call.
        pool.relockProtectedSpace(try XCTUnwrap(pool.browser.spaceModel(openSpace.id)))
        await archive.flushPendingWrites()

        XCTAssertNotNil(
            archive.archivedState(profileID: openSpace.profileID, tabID: tab.id),
            "An open Space is never relocked, so nothing of its is purged."
        )
    }

    func testASessionSweepKeepsClosedAndDeletedArchiveState() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let live = TabState.Seed(title: "Live", url: url, placement: .current)
        let closed = TabState.Seed(title: "Closed", url: url, placement: .current)
        let deleted = TabState.Seed(title: "Deleted", url: url, placement: .current)
        let space = makeSpace(tabs: [live, closed, deleted], selectedTabID: live.id)
        for tab in [live, closed, deleted] {
            archive.archive(
                interactionState: Data("state".utf8),
                url: url,
                history: nil,
                profileID: space.profileID,
                tabID: tab.id
            )
        }
        await archive.flushPendingWrites()
        let browser = hosting(space)
        let pool = BrowserPagePool(
            browser: browser,
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        XCTAssertTrue(browser.closeTab(closed.id))
        browser.deleteTab(deleted.id, in: space.id)
        pool.reconcile()
        await archive.flushPendingWrites()

        XCTAssertNotNil(
            archive.archivedState(profileID: space.profileID, tabID: live.id)
        )
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profileID, tabID: closed.id),
            "A closed tab can be reopened, so its state is worth keeping."
        )
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profileID, tabID: deleted.id),
            "A deliberate deletion now leaves a recoverable archive audit."
        )
    }

    func testAnAdoptedPopupIsNeverArchived() async throws {
        let archive = try makeTabStateArchive()
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext(tabStateArchive: archive)

        _ = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )
        let popupTabID = try XCTUnwrap(context.pool.activeTabID)
        let popupPage = try XCTUnwrap(context.pool.activePage)
        context.pool.archiveResidentTabStates()
        context.pool.unloadPage(for: popupTabID)
        await archive.flushPendingWrites()

        XCTAssertTrue(popupPage.wasOpenedAsPopup)
        XCTAssertNil(
            archive.archivedState(
                profileID: popupPage.profileID,
                tabID: popupTabID
            ),
            "WebKit drives an adopted popup's window, so Ode never archives it."
        )
    }

    /// Loads `url` as a simulated response so a back/forward entry exists without
    /// a network fixture, and waits for WebKit to commit it.
    private func load(_ url: URL, in page: BrowserPage) async throws {
        page.webView.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        page.webView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: """
                <!doctype html><html><body style="height: 4000px">\(url.path)</body></html>
                """
        )
        try await waitForLoad(url, in: page.webView)
    }

    private func makeTabStateArchive() throws -> BrowserTabStateArchive {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("crest-pool-tab-state-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return BrowserTabStateArchive(rootDirectory: root)
    }

    private func makePopupContext(
        browsingMode: BrowserBrowsingMode = .standard,
        tabStateArchive: (any BrowserTabStateArchiving)? = nil
    ) throws -> PopupAdoptionContext {
        let openerTab = TabState.Seed(title: "Opener", url: nil, placement: .current)
        let space = makeSpace(tabs: [openerTab], selectedTabID: openerTab.id)
        let store = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: fixtureSelections
        )
        let pool = BrowserPagePool(
            browser: store,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: tabStateArchive == nil,
            tabStateArchive: tabStateArchive
        )
        pool.select()
        return PopupAdoptionContext(
            store: store,
            pool: pool,
            opener: try XCTUnwrap(pool.activePage)
        )
    }

    private func makeModifiedLinkContext() throws -> ModifiedLinkContext {
        let sourceTab = TabState.Seed(title: "Source", url: nil, placement: .current)
        let space = makeSpace(tabs: [sourceTab], selectedTabID: sourceTab.id)
        let store = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: fixtureSelections
        )
        let pool = BrowserPagePool(
            browser: store,
            openModifiedLink: { url, spaceID, selecting, opener in
                store.openModifiedLink(url, in: spaceID, selecting: selecting, openedFrom: opener)
            }
        )
        pool.select()
        return ModifiedLinkContext(
            store: store,
            pool: pool,
            sourcePage: try XCTUnwrap(pool.activePage),
            sourceTabID: sourceTab.id,
            spaceID: space.id
        )
    }

    /// Waits for `webView` to finish loading `url`.
    private func waitForLoad(_ url: URL, in webView: WKWebView) async throws {
        try await waitUntil("\(url) to load", timeout: .seconds(4), interval: .milliseconds(20)) {
            webView.url == url && !webView.isLoading
        }
    }

    private func mountForFocus(_ page: BrowserPage) -> PageFocusMount {
        let host = BrowserWebHostView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480)
        )
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.attach(page.webView, focusRestoration: page.focusRestoration)
        addTeardownBlock {
            window.orderOut(nil)
            host.detach()
        }
        return PageFocusMount(window: window, host: host)
    }

    private func mountSplitForFocus(
        _ firstPage: BrowserPage,
        _ secondPage: BrowserPage
    ) -> SplitPageFocusMount {
        let content = NSView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 480)
        )
        let firstHost = BrowserWebHostView(
            frame: NSRect(x: 0, y: 0, width: 396, height: 480)
        )
        let secondHost = BrowserWebHostView(
            frame: NSRect(x: 404, y: 0, width: 396, height: 480)
        )
        content.addSubview(firstHost)
        content.addSubview(secondHost)
        let window = NSWindow(
            contentRect: content.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        firstHost.attach(
            firstPage.webView,
            focusRestoration: firstPage.focusRestoration
        )
        secondHost.attach(
            secondPage.webView,
            focusRestoration: secondPage.focusRestoration
        )
        addTeardownBlock {
            window.orderOut(nil)
            firstHost.detach()
            secondHost.detach()
        }
        return SplitPageFocusMount(
            window: window,
            firstHost: firstHost,
            secondHost: secondHost
        )
    }

    private func hosting(_ spaces: SpaceState.Seed..., on core: OdeCore = .hostingPages()) -> BrowserStore {
        .hostingPages(SessionState.Seed(spaces: spaces), showing: spaces.first?.id, tabs: fixtureSelections, core: core)
    }

    private func makeSpace(
        tabs: [TabState.Seed],
        selectedTabID: UUID,
        accessPolicy: SpaceAccessPolicy = .open
    ) -> SpaceState.Seed {
        showing(
            selectedTabID,
            in: SpaceState.Seed(name: "Test", symbol: "circle", accent: .indigo, tabs: tabs, accessPolicy: accessPolicy)
        )
    }

    /// Which tab each fixture Space shows. Selection is window state, so the
    /// fixtures keep it beside the session rather than inside it.
    private var fixtureSelections: [UUID: UUID] = [:]

    private func showing(_ tabID: UUID, in space: SpaceState.Seed) -> SpaceState.Seed {
        fixtureSelections[space.id] = tabID
        return space
    }

    /// Shows tab `tabID` of Space `spaceID` in `pool`'s window, then presents
    /// what the window shows.
    private func present(_ pool: BrowserPagePool, tab tabID: UUID, in spaceID: UUID, at time: Date = .now) {
        pool.browser.selectSpace(spaceID)
        pool.browser.selectTab(tabID)
        pool.select(at: time)
    }

    /// Shows Space `spaceID` in `pool`'s window on the tab the fixture names
    /// for it, then presents what the window shows.
    private func present(_ pool: BrowserPagePool, showing spaceID: UUID) {
        pool.browser.selectSpace(spaceID)
        if let tabID = fixtureSelections[spaceID] { pool.browser.selectTab(tabID) }
        pool.select()
    }

}

private struct PageFocusMount {
    let window: NSWindow
    let host: BrowserWebHostView
}

private struct SplitPageFocusMount {
    let window: NSWindow
    let firstHost: BrowserWebHostView
    let secondHost: BrowserWebHostView
}

final class BrowserPageLifecyclePolicyTests: XCTestCase {
    func testTheCoalescerCollapsesOneSqueezeWithoutSwallowingAnEscalation() {
        var coalescer = BrowserMemoryPressureCoalescer()
        let squeeze = Date()

        XCTAssertTrue(coalescer.shouldHandle(.warning, at: squeeze))
        XCTAssertFalse(
            coalescer.shouldHandle(.warning, at: squeeze.addingTimeInterval(0.05)),
            "The second signal for one squeeze must not be handled again."
        )
        XCTAssertTrue(
            coalescer.shouldHandle(.critical, at: squeeze.addingTimeInterval(0.1)),
            "Critical pressure can release transients preserved by a warning."
        )
        XCTAssertFalse(
            coalescer.shouldHandle(.critical, at: squeeze.addingTimeInterval(0.15))
        )
        XCTAssertFalse(
            coalescer.shouldHandle(.warning, at: squeeze.addingTimeInterval(0.2)),
            "A warning trailing a critical squeeze has nothing left to ask for."
        )
        XCTAssertTrue(
            coalescer.shouldHandle(
                .warning,
                at: squeeze.addingTimeInterval(
                    BrowserMemoryPressureCoalescer.defaultWindow * 2
                )
            ),
            "Pressure that outlives the window is a new squeeze."
        )
    }

    func testAClockThatJumpedIsNeverAReasonToSkipPressureHandling() {
        var coalescer = BrowserMemoryPressureCoalescer()
        let squeeze = Date()

        XCTAssertTrue(coalescer.shouldHandle(.warning, at: squeeze))
        XCTAssertTrue(
            coalescer.shouldHandle(.warning, at: squeeze.addingTimeInterval(-60))
        )
    }
}

@MainActor
private struct ModifiedLinkContext {
    let store: BrowserStore
    let pool: BrowserPagePool
    let sourcePage: BrowserPage
    let sourceTabID: UUID
    let spaceID: UUID

    var openedTabs: [TabStateModel] {
        store.shownSpace?.tabs.models.filter { $0.id != sourceTabID } ?? []
    }

    func open(_ url: URL, selecting: Bool) {
        sourcePage.openModifiedLink(URLRequest(url: url), spaceID, selecting)
    }
}

/// One opener page, its pool, and the store that owns their tabs, so popup tests
/// drive the real `WKUIDelegate` entry point instead of the pool's adoption API.
@MainActor
private struct PopupAdoptionContext {
    let store: BrowserStore
    let pool: BrowserPagePool
    let opener: BrowserPage

    /// Hands the opener a configuration copied from its own, which is what WebKit
    /// does before calling `createWebViewWith`.
    func requestPopup(url: URL?, navigationType: WKNavigationType) -> WKWebView? {
        try? opener.requestTestPopup(url: url, navigationType: navigationType)
    }
}

@MainActor
extension BrowserPage {
    /// Drives the real `WKUIDelegate` entry point with the configuration WebKit
    /// would copy from this opener.
    func requestTestPopup(
        url: URL?,
        navigationType: WKNavigationType
    ) throws -> WKWebView? {
        let configuration = try XCTUnwrap(
            webView.configuration.copy() as? WKWebViewConfiguration
        )
        return webView(
            webView,
            createWebViewWith: configuration,
            for: StubPopupNavigationAction(
                url: url,
                navigationType: navigationType
            ),
            windowFeatures: WKWindowFeatures()
        )
    }
}

/// WebKit never lets an app build a real `WKNavigationAction`, so popup tests
/// stand in for the one WebKit hands to `createWebViewWith`: no target frame and
/// a navigation type that selects the popup trigger under test.
final class StubPopupNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
    private let stubRequest: URLRequest
    private let stubNavigationType: WKNavigationType
    private let stubModifierFlags: NSEvent.ModifierFlags

    init(url: URL?, navigationType: WKNavigationType, modifierFlags: NSEvent.ModifierFlags = []) {
        // `window.open()` without a destination reaches WebKit as a request
        // without a URL, which a stub can only reproduce by clearing it.
        var request = URLRequest(url: URL(fileURLWithPath: "/"))
        request.url = url
        stubRequest = request
        stubNavigationType = navigationType
        stubModifierFlags = modifierFlags
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { stubNavigationType }
    override var targetFrame: WKFrameInfo? { nil }
    override var modifierFlags: NSEvent.ModifierFlags { stubModifierFlags }
    override var buttonNumber: Int { 0 }
    var browserSourceOrigin: SiteOrigin? { nil }
}

@MainActor
private final class RecordingWebsiteDataStoreRemover:
    BrowserEngineProfileRemoving
{
    private(set) var removedProfileIDs: [UUID] = []

    func removeProfile(_ profileID: UUID, ephemeral: Bool) async throws {
        removedProfileIDs.append(profileID)
    }
}

private final class PagePoolAuthenticationChallengeSenderStub:
    NSObject,
    URLAuthenticationChallengeSender
{
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}

extension SpaceState.Seed {
}
