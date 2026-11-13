import WebKit
import XCTest

@testable import OdeMobile

@MainActor
final class MobileBrowserRootModelTests: XCTestCase {
    func testStartPageFocusSurvivesLayoutChangesButRejectsAnotherTabOrSpace() throws {
        let first = makeSpace(index: 10)
        let second = makeSpace(index: 20)
        let fixture = makeFixture(spaces: [first, second], selectedSpaceID: first.id, startupBehavior: .lastActiveTab)
        fixture.model.beginCompactNewTab()
        let originalFocus = fixture.model.startPageQueryFocusBinding
        originalFocus.wrappedValue = true
        fixture.model.presentationChanged(to: .regular)
        fixture.model.presentationChanged(to: .compact)
        XCTAssertTrue(fixture.model.startPageQueryFocusBinding.wrappedValue)

        let originalTabID = fixture.browser.shownTab?.id
        fixture.browser.navigateSelectedTab(to: "http://127.0.0.1/completed-start-page")
        fixture.model.beginCompactNewTab()
        XCTAssertNotNil(originalTabID)
        XCTAssertNotEqual(fixture.browser.shownTab?.id, originalTabID)
        XCTAssertFalse(fixture.model.startPageQueryFocusBinding.wrappedValue)
        originalFocus.wrappedValue = true
        XCTAssertFalse(fixture.model.startPageQueryFocusBinding.wrappedValue)
        fixture.model.startPageQueryFocusBinding.wrappedValue = true
        fixture.browser.selectSpace(second.id)
        XCTAssertFalse(fixture.model.startPageQueryFocusBinding.wrappedValue)
        originalFocus.wrappedValue = true
        XCTAssertFalse(fixture.model.startPageQueryFocusBinding.wrappedValue)
    }

    func testDelayedPasteAndQueryCallbacksCannotOverwriteAnotherBrowsingContext() async throws {
        let transitions: [(String, (MobileBrowserRootFixture) throws -> Void)] = [
            (
                "tab",
                { fixture in
                    let source = try XCTUnwrap(fixture.browser.shownTabAssignment)
                    fixture.browser.navigateSelectedTab(to: "http://127.0.0.1/completed-start-page")
                    fixture.model.beginCompactNewTab()
                    XCTAssertNotEqual(fixture.browser.shownTabAssignment, source)
                }
            ),
            ("Space", { fixture in fixture.browser.selectSpace(fixture.browser.spaceModels[1].id) }),
            (
                "profile",
                { fixture in
                    fixture.browser.replaceProfileForTesting(
                        of: try XCTUnwrap(fixture.browser.shownSpace?.id), with: UUID())
                }
            ),
        ]
        for (name, transition) in transitions {
            let first = makeSpace(index: 10)
            let second = makeSpace(index: 20)
            let fixture = makeFixture(
                spaces: [first, second], selectedSpaceID: first.id, startupBehavior: .lastActiveTab)
            fixture.model.address = "original draft"
            let originalQuery = fixture.model.addressBinding
            let palette = BrowserCommandPaletteModel(
                browser: fixture.browser, space: fixture.browser.shownSpace,
                selectedTabID: fixture.browser.shownTab?.id, initialQuery: originalQuery.wrappedValue, commands: nil,
                lookups: BrowserCommandPaletteLookups(
                    fetchSuggestions: { _ in [] }, isOnline: { false }, lookUpDefinition: { _ in nil },
                    fetchWebSummary: { _ in nil }),
                isSourceAvailable: { fixture.model.isPaletteSourceAvailable($0) },
                selectTab: { _, _ in
                    XCTFail("Unexpected tab selection")
                    return false
                },
                openURL: { _, _, _ in
                    XCTFail("Unexpected navigation")
                    return false
                }, dismiss: {})
            let view = BrowserPlatformCommandPaletteField(
                model: palette, presentation: .embedded, identifier: "delayed-paste-field", focused: false)
            let coordinator = view.makeCoordinator()
            let field = view.makeField(coordinator: coordinator)
            XCTAssertTrue(palette.isCompletionSourceAvailable, name)
            // A query notification can already be queued when the system's
            // asynchronous Paste payload returns after the selection changes.
            let queuedQuery = palette.query
            try transition(fixture)
            fixture.model.address = "destination draft"
            XCTAssertFalse(palette.isCompletionSourceAvailable, name)
            XCTAssertEqual(originalQuery.wrappedValue, "", name)
            let completion = Task { @MainActor in
                await Task.yield()
                coordinator.insertPastedText(" delayed payload")
                originalQuery.wrappedValue = queuedQuery
            }
            await completion.value
            XCTAssertEqual(field.text, "original draft", name)
            XCTAssertEqual(palette.query, "original draft", name)
            XCTAssertEqual(fixture.model.address, "destination draft", name)
        }
    }

    /// Folding a phone returns to what its narrow window last showed, except
    /// after a tab was chosen while the window was wide: then the narrow
    /// window shows that tab's page, never the tab viewer.
    func testNarrowingAfterChoosingATabInTheWideWindowShowsItsPage() throws {
        var space = makeSpace(index: 40)
        let chosen = TabState.Seed(title: "Chosen", url: URL(string: "about:blank"), placement: .current)
        space.tabs.append(chosen)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .compact)
        XCTAssertFalse(fixture.navigation.compactShowsPage)

        fixture.model.presentationChanged(to: .regular)
        fixture.model.presentationChanged(to: .compact)
        XCTAssertFalse(fixture.navigation.compactShowsPage)

        fixture.model.presentationChanged(to: .regular)
        fixture.model.selectTab(chosen.id)
        fixture.model.presentationChanged(to: .compact)

        XCTAssertEqual(fixture.browser.shownTab?.id, chosen.id)
        XCTAssertTrue(fixture.navigation.compactShowsPage)
        XCTAssertFalse(fixture.navigation.compactToolbarIsHidden)
    }

    func testLockImmediatelyRevokesRetainedPageActionsBeforeReconciliation() async throws {
        var space = makeSpace(index: 52)
        space.settings.accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(authenticator: AcceptingAuthenticator())
        let fixture = makeFixture(
            spaces: [space], selectedSpaceID: space.id,
            startupBehavior: .lastActiveTab, spaceAccess: access
        )
        let unlocked = await access.unlock(try XCTUnwrap(fixture.browser.spaceModel(space.id)))
        XCTAssertTrue(unlocked)
        fixture.model.presentationChanged(to: .regular)
        await fixture.model.prepareBrowser()
        let page = try XCTUnwrap(fixture.model.selectedPage)
        let actions = try XCTUnwrap(fixture.model.selectedPageActions)
        XCTAssertTrue(actions.isAvailable)
        let session = fixture.browser.sessionSeed

        access.lock(space.id)
        actions.presentFind()
        fixture.model.synchronizePageMetadata(isAddressEditing: false)

        XCTAssertTrue(fixture.pages.activePage === page)
        XCTAssertNil(fixture.model.selectedPage)
        XCTAssertFalse(actions.isAvailable)
        XCTAssertNil(actions.pageAssignment)
        XCTAssertNil(actions.activeURL)
        XCTAssertFalse(page.isFindPresented)
        XCTAssertEqual(fixture.browser.sessionSeed, session)

        let unlockedAgain = await access.unlock(try XCTUnwrap(fixture.browser.spaceModel(space.id)))
        XCTAssertTrue(unlockedAgain)
        XCTAssertTrue(actions.isAvailable)
        XCTAssertTrue(actions.activePage === page)
    }

    func testFreshCommandRequestWaitsForReadinessOnboardingAndUnlockThenConsumesOnce() async throws {
        var space = makeSpace(index: 61)
        space.settings.accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(authenticator: AcceptingAuthenticator())
        let fixture = makeFixture(
            spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab, spaceAccess: access)
        let original = fixture.browser.sessionSeed
        fixture.navigation.requestFreshQuery()
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        await fixture.model.prepareBrowser()
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertFalse(fixture.model.beginFreshQuery())
        XCTAssertEqual(fixture.model.freshQueryRevision, 0)
        XCTAssertEqual(fixture.browser.sessionSeed, original)
        XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
        let unlocked = await access.unlock(try XCTUnwrap(fixture.browser.shownSpace))
        XCTAssertTrue(unlocked)
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: false, isObscured: false))
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: true))
        XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
        XCTAssertTrue(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertFalse(fixture.navigation.hasPendingFreshQuery)
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertEqual(fixture.browser.shownSpace?.id, space.id)
        XCTAssertEqual(fixture.browser.shownSpace?.profileID, space.profileID)
        XCTAssertEqual(fixture.browser.sessionSeed, original)
    }

    func testRepeatedFreshQueryRevokesOldPaletteAndQueuedDraftInSameBrowsingContext() async throws {
        let space = makeSpace(index: 62)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        XCTAssertTrue(fixture.model.beginFreshQuery())
        fixture.model.address = "old draft"
        let oldQuery = fixture.model.addressBinding
        let oldSourceGate = fixture.model.paletteSourceAvailability
        let oldFocus = fixture.model.startPageQueryFocusBinding
        let source = try XCTUnwrap(fixture.browser.shownTabAssignment)
        XCTAssertTrue(oldSourceGate(source))
        let core = fixture.browser.core
        let palette = BrowserCommandPaletteModel(
            browser: fixture.browser, space: fixture.browser.shownSpace, selectedTabID: source.tabID,
            initialQuery: "https://old.example.test/", commands: nil,
            lookups: BrowserCommandPaletteLookups(
                fetchSuggestions: { _ in [] }, isOnline: { false }, lookUpDefinition: { _ in nil },
                fetchWebSummary: { _ in nil },
                answer: { question in
                    try? await Task.sleep(for: .milliseconds(50))
                    return try? core.query(question)
                }),
            isSourceAvailable: oldSourceGate,
            selectTab: { _, _ in
                XCTFail("Old palette selected a tab")
                return false
            },
            openURL: { _, _, _ in
                XCTFail("Old palette navigated")
                return false
            }, dismiss: {})
        palette.query = "https://pending.example.test/"
        palette.pressReturn()
        let revision = fixture.model.freshQueryRevision
        let before = fixture.browser.sessionSeed

        XCTAssertTrue(fixture.model.beginFreshQuery())

        XCTAssertEqual(fixture.model.freshQueryRevision, revision + 1)
        XCTAssertEqual(fixture.model.address, "")
        XCTAssertFalse(oldSourceGate(source))
        XCTAssertTrue(fixture.model.paletteSourceAvailability(source))
        oldQuery.wrappedValue = "late old answer or paste"
        oldFocus.wrappedValue = true
        XCTAssertFalse(fixture.model.startPageQueryFocusBinding.wrappedValue)
        XCTAssertFalse(palette.isCompletionSourceAvailable)
        // The shared mounted palette forwards this observed source change to
        // its cancellation handler before final disappearance clears query.
        palette.sourceAvailabilityChanged(palette.isCompletionSourceAvailable)
        await palette.waitForPendingResults()
        XCTAssertTrue(palette.items.isEmpty)
        palette.stop()
        XCTAssertEqual(palette.query, "")
        XCTAssertEqual(fixture.model.address, "")
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        fixture.model.addressBinding.wrappedValue = "new draft"
        XCTAssertEqual(fixture.model.address, "new draft")
    }

    func testWidgetRequestWaitsForRealSettingsWithoutChangingThePage() async throws {
        let space = makeSpace(index: 65)
        for mode in [BrowserBrowsingMode.standard, .privateBrowsing] {
            let fixture = makeFixture(
                spaces: [space], selectedSpaceID: space.id, browsingMode: mode, startupBehavior: .lastActiveTab)
            fixture.browser.navigateSelectedTab(to: "http://127.0.0.1/retained-page")
            fixture.model.presentationChanged(to: .compact)
            await fixture.model.prepareBrowser()
            fixture.model.activateSelectedTab()
            let page = try XCTUnwrap(fixture.model.selectedPage)
            fixture.model.openSettings()
            XCTAssertTrue(fixture.model.settings.showsSheet)
            fixture.model.settings.reconcile()
            XCTAssertTrue(fixture.model.settings.showsSheet)
            fixture.model.settings.sheetDidAppear()
            let before = fixture.browser.sessionSeed
            let selected = fixture.browser.shownTabAssignment
            fixture.navigation.requestFreshQuery()

            XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
            XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
            XCTAssertEqual(fixture.browser.sessionSeed, before)
            XCTAssertEqual(fixture.browser.shownTabAssignment, selected)
            XCTAssertTrue(fixture.model.selectedPage === page)
            XCTAssertFalse(fixture.model.settings.showsSheet)
            XCTAssertTrue(fixture.model.settings.awaitsSheetDismissal)
            // A false sheet binding is not a native dismissal completion.
            XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
            XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
            XCTAssertEqual(fixture.browser.sessionSeed, before)
            fixture.model.settings.sheetDidDismiss()
            XCTAssertTrue(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
            XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
            XCTAssertTrue(fixture.model.beginFreshQuery())
            fixture.model.beginCompactNewTab()
            let fresh = fixture.browser.shownTabAssignment
            XCTAssertNotEqual(fresh, selected)
            XCTAssertEqual(fixture.browser.shownTab?.surface, .startPage)
            XCTAssertEqual(fixture.browser.shownSpace?.id, space.id)
            XCTAssertEqual(fixture.browser.shownSpace?.profileID, space.profileID)
            fixture.navigation.requestFreshQuery()
            XCTAssertTrue(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
            XCTAssertTrue(fixture.model.beginFreshQuery())
            fixture.model.beginCompactNewTab()
            XCTAssertEqual(fixture.browser.shownTabAssignment, fresh)
            XCTAssertFalse(fixture.navigation.hasPendingFreshQuery)
        }
    }

    func testWidgetRequestWaitsForEachOwnedListDismissalWithoutChangingOtherScene() async throws {
        let space = makeSpace(index: 67)
        let otherScene = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        let otherBefore = otherScene.browser.sessionSeed
        for surface in [BrowserUtilitySurface.history, .downloads, .archive] {
            let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
            await fixture.model.prepareBrowser()
            fixture.model.presentedListSheet = MobileBrowserSidebarSpaceSheet(
                surface: surface,
                assignment: BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(fixture.browser.shownSpace)))
            fixture.model.listSheetDidAppear()
            let before = fixture.browser.sessionSeed
            fixture.navigation.requestFreshQuery()
            XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
            XCTAssertNil(fixture.model.presentedListSheet)
            XCTAssertTrue(fixture.model.awaitsListSheetDismissal)
            XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
            XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
            XCTAssertEqual(fixture.browser.sessionSeed, before)
            fixture.model.listSheetDidDismiss()
            XCTAssertTrue(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
            XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
            XCTAssertEqual(fixture.browser.sessionSeed, before)
            XCTAssertEqual(otherScene.browser.sessionSeed, otherBefore)
            XCTAssertFalse(otherScene.navigation.hasPendingFreshQuery)
        }
    }

    func testWidgetRequestNeverDismissesAnUnansweredDownloadRiskDecision() async throws {
        let space = makeSpace(index: 68)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .compact)
        await fixture.model.prepareBrowser()
        fixture.model.openSettings()
        fixture.model.settings.sheetDidAppear()
        let confirmation = fixture.pages.downloadRiskConfirmation
        let approval = Task { @MainActor in
            await confirmation.requestApproval(
                assessment: DownloadRiskAssessment(sanitizedFilename: "unsafe.exe", reasons: [.executableOrInstaller]),
                sourceURL: nil, spaceName: "Test", profileID: space.profileID)
        }
        while confirmation.request == nil { await Task.yield() }
        let requestID = confirmation.request?.id
        let before = fixture.browser.sessionSeed
        fixture.navigation.requestFreshQuery()
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertEqual(confirmation.request?.id, requestID)
        XCTAssertTrue(fixture.model.settings.showsSheet)
        XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        confirmation.cancel()
        let approved = await approval.value
        XCTAssertFalse(approved)
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        fixture.model.settings.sheetDidDismiss()
        XCTAssertTrue(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
    }

    func testPasswordsActionKeepsWidgetEntryPendingUntilNativeDismissal() async throws {
        let space = makeSpace(index: 70)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.browser.navigateSelectedTab(to: "http://127.0.0.1/passwords-owner-page")
        fixture.model.presentationChanged(to: .regular)
        await fixture.model.prepareBrowser()
        let page = try XCTUnwrap(fixture.model.selectedPage)
        let before = fixture.browser.sessionSeed
        let selected = fixture.browser.shownTabAssignment
        // This is the Space-header Passwords action's production endpoint.
        fixture.model.openPasswords()
        fixture.model.passwordsSheetDidAppear()
        fixture.navigation.requestFreshQuery()

        XCTAssertTrue(fixture.model.showsPasswords)
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertTrue(fixture.model.showsPasswords)
        XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        XCTAssertEqual(fixture.browser.shownTabAssignment, selected)
        XCTAssertTrue(fixture.model.selectedPage === page)
        // Authentication/credential edits finish normally. Binding reset
        // starts dismissal but does not yet make input revealable.
        fixture.model.dismissPasswords()
        XCTAssertTrue(fixture.model.awaitsPasswordsSheetDismissal)
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        fixture.model.passwordsSheetDidDismiss()
        XCTAssertTrue(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertEqual(fixture.browser.sessionSeed, before)
    }

    func testNestedPasswordsActionProtectsOuterSettingsUntilNormalChildDismissal() async throws {
        let space = makeSpace(index: 71)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .compact)
        await fixture.model.prepareBrowser()
        fixture.model.openSettings()
        fixture.model.settings.sheetDidAppear()
        let before = fixture.browser.sessionSeed
        // Settings' Manage Saved Passwords action uses this same owner;
        // its native sheet waits for the manager's operation-state report.
        fixture.model.openPasswords(fromSettings: true)
        fixture.model.passwordsSheetDidAppear()
        fixture.navigation.requestFreshQuery()

        XCTAssertTrue(fixture.model.passwordsArePresentedFromSettings)
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertTrue(fixture.model.settings.showsSheet)
        XCTAssertFalse(fixture.model.settings.awaitsSheetDismissal)
        XCTAssertTrue(fixture.model.showsPasswords)
        XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        fixture.model.dismissPasswords()
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertTrue(fixture.model.settings.showsSheet)
        fixture.model.passwordsSheetDidDismiss()
        // Finishing the child decision permits the existing outer navigation
        // dismissal, not consumption underneath that still-visible sheet.
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertFalse(fixture.model.settings.showsSheet)
        XCTAssertTrue(fixture.model.settings.awaitsSheetDismissal)
        XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        fixture.model.settings.sheetDidDismiss()
        XCTAssertTrue(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertEqual(fixture.browser.sessionSeed, before)
    }

    func testIdleNestedPasswordsPresentationClosesBeforeSettingsAndConsumesOnce() async throws {
        let space = makeSpace(index: 72)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .compact)
        await fixture.model.prepareBrowser()
        fixture.model.openSettings()
        fixture.model.settings.sheetDidAppear()
        fixture.model.openPasswords(fromSettings: true)
        fixture.model.passwordsSheetDidAppear()
        let presentation = fixture.model.passwordsPresentation(fromSettings: true)
        let before = fixture.browser.sessionSeed
        fixture.navigation.requestFreshQuery()

        // A manager whose operation state has not arrived is protected.
        XCTAssertTrue(presentation.wrappedValue)
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertTrue(presentation.wrappedValue)
        fixture.model.passwordsPendingOperationChanged(false)
        // A credential decision can start after the manager became idle.
        fixture.model.passwordsPendingOperationChanged(true)
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertTrue(presentation.wrappedValue)
        XCTAssertTrue(fixture.model.settings.showsSheet)

        fixture.model.passwordsPendingOperationChanged(false)
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        // The production binding must reflect the root's close request,
        // without simulating a manual Done/binding reset in the test.
        XCTAssertFalse(presentation.wrappedValue)
        XCTAssertTrue(fixture.model.awaitsPasswordsSheetDismissal)
        XCTAssertTrue(fixture.model.settings.showsSheet)
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        fixture.model.passwordsSheetDidDismiss()
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertFalse(fixture.model.settings.showsSheet)
        XCTAssertTrue(fixture.model.settings.awaitsSheetDismissal)
        XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        fixture.model.settings.sheetDidDismiss()
        XCTAssertTrue(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertEqual(fixture.browser.sessionSeed, before)
    }

    func testSharedPrivateDownloadDecisionBlocksOnlyItsOwningSceneWidgetEntry() async throws {
        let browser = BrowserStore.hostingPages(
            .preview, core: .hostingPages(contentRuleLists: EmptyMobileRootContentRuleListProvider()))
        let permissions = BrowserSitePermissionCenter(core: browser.core)
        let downloads = MobileBrowserDownloads(
            core: browser.core, browsingMode: .privateBrowsing, permissionCenter: permissions)
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true))
        func makeScene() -> MobileBrowserWindowSceneModel {
            MobileBrowserWindowSceneModel(
                id: UUID(), rootBrowser: browser, permissionCenter: permissions,
                pageStoreRegistry: registry, spaceAccess: BrowserSpaceAccessController(), tabStateArchive: nil,
                windowLayouts: BrowserWindowLayouts(defaults: nil), startupBehavior: .lastActiveTab,
                usesEphemeralWebsiteDataStores: true, privateDownloads: downloads)
        }
        func makePrivateRoot(_ scene: MobileBrowserWindowSceneModel) -> MobileBrowserRootModel {
            MobileBrowserRootModel(
                browser: scene.privateBrowser, pages: scene.privatePages, navigation: scene.privateNavigation,
                spaceAccess: scene.spaceAccess, windowState: scene.windowState,
                startupBehavior: .lastActiveTab,
                persistedSidebarWidth: MobileBrowserRootLayout.defaultRegularSidebarWidth)
        }
        let owningScene = makeScene()
        let receivingScene = makeScene()
        defer {
            owningScene.closeWindowRuntime()
            receivingScene.closeWindowRuntime()
        }
        let owner = makePrivateRoot(owningScene)
        let receiver = makePrivateRoot(receivingScene)
        await owner.prepareBrowser()
        await receiver.prepareBrowser()
        let ownerSpace = try XCTUnwrap(owner.browser.shownSpace)
        let receiverSpace = try XCTUnwrap(receiver.browser.shownSpace)
        XCTAssertNotEqual(owner.browser.family.workspaceID, receiver.browser.family.workspaceID)
        XCTAssertNotEqual(ownerSpace.profileID, receiverSpace.profileID)
        XCTAssertTrue(owner.pages.downloadRiskConfirmation === downloads.riskConfirmation)
        XCTAssertTrue(receiver.pages.downloadRiskConfirmation === downloads.riskConfirmation)
        let approval = Task { @MainActor in
            await downloads.riskConfirmation.requestApproval(
                assessment: DownloadRiskAssessment(sanitizedFilename: "unsafe.exe", reasons: [.executableOrInstaller]),
                sourceURL: nil, spaceName: ownerSpace.settings.name, profileID: ownerSpace.profileID)
        }
        while downloads.riskConfirmation.request == nil { await Task.yield() }
        let requestID = downloads.riskConfirmation.request?.id
        let ownerBefore = owner.browser.sessionSeed
        let receiverBefore = receiver.browser.sessionSeed
        XCTAssertTrue(owningScene.routeCommandURL(BrowserCommandLink.newQuery.url, browsingMode: .privateBrowsing))
        XCTAssertTrue(receivingScene.routeCommandURL(BrowserCommandLink.newQuery.url, browsingMode: .privateBrowsing))

        XCTAssertTrue(owner.hasPendingDecision)
        XCTAssertFalse(receiver.hasPendingDecision)
        XCTAssertFalse(owner.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertTrue(receiver.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertFalse(receiver.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertTrue(owner.navigation.hasPendingFreshQuery)
        XCTAssertFalse(receiver.navigation.hasPendingFreshQuery)
        XCTAssertFalse(owningScene.navigation.hasPendingFreshQuery)
        XCTAssertFalse(receivingScene.navigation.hasPendingFreshQuery)
        XCTAssertEqual(downloads.riskConfirmation.request?.id, requestID)
        XCTAssertEqual(downloads.riskConfirmation.request?.profileID, ownerSpace.profileID)
        XCTAssertEqual(owner.browser.sessionSeed, ownerBefore)
        XCTAssertEqual(receiver.browser.sessionSeed, receiverBefore)

        downloads.riskConfirmation.cancel()
        let approved = await approval.value
        XCTAssertFalse(approved)
        XCTAssertTrue(owner.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertFalse(owner.consumeFreshQueryRequest(isReady: true, isObscured: false))
    }

    func testDetachedNativeRootDoesNotStrandPendingEntryOnOldSheetDismissals() async throws {
        let space = makeSpace(index: 69)
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .compact)
        await fixture.model.prepareBrowser()
        fixture.model.openSettings()
        fixture.model.settings.sheetDidAppear()
        fixture.navigation.requestFreshQuery()
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertTrue(fixture.model.settings.awaitsSheetDismissal)
        let observer = MobileBrowserRootWindowObserver.WindowView()
        observer.model = fixture.model
        // Native host teardown, not an invented obscured flag, clears gates
        // whose old SwiftUI host can no longer deliver onDismiss.
        observer.didMoveToWindow()
        XCTAssertFalse(fixture.model.settings.awaitsSheetDismissal)
        XCTAssertTrue(fixture.navigation.hasPendingFreshQuery)
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: false, isObscured: false))
        XCTAssertTrue(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
        XCTAssertFalse(fixture.model.consumeFreshQueryRequest(isReady: true, isObscured: false))
    }

    func testFreshEmptySelectionRejectsQueuedReturnBeforePaletteDisappears() async throws {
        var space = makeSpace(index: 66)
        space.tabs = []
        let fixture = makeFixture(spaces: [space], selectedSpaceID: space.id, startupBehavior: .lastActiveTab)
        fixture.model.presentationChanged(to: .regular)
        XCTAssertNil(fixture.browser.shownTab)
        let destination = BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(fixture.browser.shownSpace)),
            browser: fixture.browser, accessController: fixture.model.spaceAccess, didSelectTab: {},
            isSourceAvailable: fixture.model.freshQueryAvailability)
        let core = fixture.browser.core
        let gate = MobileRootAnswerGate()
        let palette = BrowserCommandPaletteModel(
            browser: fixture.browser, space: fixture.browser.shownSpace, selectedTabID: nil,
            initialQuery: "", commands: nil,
            lookups: BrowserCommandPaletteLookups(
                fetchSuggestions: { _ in [] }, isOnline: { false }, lookUpDefinition: { _ in nil },
                fetchWebSummary: { _ in nil },
                answer: { question in
                    await gate.wait()
                    return try? core.query(question)
                }),
            isSourceAvailable: fixture.model.paletteSourceAvailability,
            selectTab: { _, _ in false }, openURL: { _, _, _ in false },
            dismiss: {}, destination: destination)
        palette.query = "https://stale.example.test/"
        palette.pressReturn()
        await gate.waitUntilStarted()
        let before = fixture.browser.sessionSeed
        XCTAssertTrue(fixture.model.beginFreshQuery())
        XCTAssertFalse(palette.isCompletionSourceAvailable)
        gate.release()
        await palette.waitForPendingResults()
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        XCTAssertNil(fixture.browser.shownTab)
        let staleURL = try XCTUnwrap(URL(string: "https://stale-dispatch.example.test/"))
        XCTAssertFalse(destination.openURL(staleURL))
        XCTAssertEqual(fixture.browser.sessionSeed, before)
        let current = BrowserEmptySelectionPaletteActions(
            source: destination.source, browser: fixture.browser, accessController: fixture.model.spaceAccess,
            didSelectTab: {}, isSourceAvailable: fixture.model.freshQueryAvailability)
        XCTAssertTrue(current.isAvailable)
        XCTAssertTrue(current.openURL(staleURL))
        palette.stop()
    }

    func testPendingCommandEntryPreservesReceivingSpaceInsteadOfPassiveStartupDefault() async {
        var first = makeSpace(index: 63)
        var receiving = makeSpace(index: 64)
        first.tabs = []
        receiving.tabs = []
        for hasRequest in [false, true] {
            let fixture = makeFixture(
                spaces: [first, receiving], selectedSpaceID: receiving.id, startupBehavior: .newTab,
                defaultSpaceID: first.id)
            if hasRequest { fixture.navigation.requestFreshQuery() }
            let before = fixture.browser.sessionSeed
            let opensLaunchTab = await fixture.model.prepareBrowser()
            XCTAssertTrue(fixture.model.hasPreparedBrowser)
            XCTAssertEqual(opensLaunchTab, !hasRequest)
            XCTAssertEqual(fixture.browser.shownSpace?.id, hasRequest ? receiving.id : first.id)
            XCTAssertEqual(fixture.browser.shownSpace?.profileID, hasRequest ? receiving.profileID : first.profileID)
            if hasRequest {
                XCTAssertNil(fixture.browser.shownTab)
                XCTAssertEqual(fixture.browser.sessionSeed, before)
            } else {
                // Passive default-Space selection prepares its blank tab.
                XCTAssertEqual(fixture.browser.shownTab?.surface, .startPage)
            }
            XCTAssertEqual(fixture.navigation.hasPendingFreshQuery, hasRequest)
        }
    }

    private func makeFixture(
        spaces: [SpaceState.Seed],
        selectedSpaceID: UUID,
        browsingMode: BrowserBrowsingMode = .standard,
        startupBehavior: StartupBehavior,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        defaultSpaceID: UUID? = nil
    ) -> MobileBrowserRootFixture {
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: spaces, defaultSpaceID: defaultSpaceID),
            showing: selectedSpaceID,
            // Every Space shows its first tab, as a window restoring them would.
            tabs: Dictionary(
                uniqueKeysWithValues: spaces.compactMap { space in space.tabs.first.map { (space.id, $0.id) } }),
            browsingMode: browsingMode,
            core: .hostingPages(contentRuleLists: EmptyMobileRootContentRuleListProvider())
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: true
        )
        let navigation = MobileBrowserNavigationState()
        browser.attachSpaceAccess(spaceAccess)
        let model = MobileBrowserRootModel(
            browser: browser,
            pages: pages,
            navigation: navigation,
            spaceAccess: spaceAccess,
            windowState: nil,
            startupBehavior: startupBehavior,
            persistedSidebarWidth: MobileBrowserRootLayout.defaultRegularSidebarWidth
        )
        return MobileBrowserRootFixture(
            browser: browser,
            pages: pages,
            navigation: navigation,
            model: model
        )
    }

    private func makeSpace(index: Int) -> SpaceState.Seed {
        let tab = TabState.Seed.startPage(
            id: UUID.fixed(index * 10 + 1),
            placement: .current
        )
        return SpaceState.Seed(
            id: UUID.fixed(index * 10 + 2),
            profileID: UUID.fixed(index * 10 + 3),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
    }
}

@MainActor
private final class MobileRootAnswerGate {
    private var pending: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard pending == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        pending?.resume()
        pending = nil
    }
}

@MainActor
private struct MobileBrowserRootFixture {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let model: MobileBrowserRootModel
}

@MainActor
private final class EmptyMobileRootContentRuleListProvider:
    BrowserContentRuleListProviding
{
    func balancedRuleLists() async throws -> [WKContentRuleList] { [] }
}
