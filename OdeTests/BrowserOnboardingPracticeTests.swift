import AppKit
import XCTest

@testable import Ode

@MainActor
final class BrowserOnboardingPracticeTests: XCTestCase {
    // MARK: - Actions - Input and ownership

    func testConfiguredCommandsChangeOnlyTheDisposableWorkspaceAndFeedbackFollowsTheirEffects() throws {
        let real = BrowserStore(seed: .preview)
        let original = real.sessionSeed
        let shortcuts = BrowserShortcutStore(core: real.core)
        let custom = BrowserShortcut(key: .character("y"), modifiers: [.command, .shift])
        _ = shortcuts.reassign(custom, to: .newTab)
        let practice = try BrowserOnboardingPractice(shortcuts: shortcuts)
        defer { practice.leave() }

        XCTAssertFalse(practice.foundSample)
        XCTAssertFalse(practice.handle(key("t", modifiers: .command)))
        XCTAssertFalse(practice.chrome.isCommandPalettePresented)
        XCTAssertTrue(practice.handle(key("y", modifiers: [.command, .shift])))
        XCTAssertTrue(practice.chrome.isCommandPalettePresented)
        practice.observe()
        XCTAssertFalse(practice.foundSample, "Opening a launcher is not finding the intended tab")

        // A selection in a different workspace cannot complete this moment.
        let outside = BrowserStore(seed: .preview)
        if let unrelated = outside.shownSpace?.tabs.models.first { outside.selectTab(unrelated.id) }
        practice.observe()
        XCTAssertFalse(practice.foundSample)
        practice.browser.selectTab(practice.sampleID)
        practice.observe()
        XCTAssertTrue(practice.foundSample)

        practice.actions.perform(.nextSpace)
        practice.observe()
        XCTAssertEqual(practice.browser.selectedSpaceID, practice.awayID)
        XCTAssertTrue(practice.visitedOtherSpace)
        XCTAssertFalse(practice.returnedHome)
        practice.actions.perform(.previousSpace)
        practice.observe()
        XCTAssertEqual(practice.browser.selectedSpaceID, practice.homeID)
        XCTAssertTrue(practice.returnedHome)
        XCTAssertNotNil(practice.browser.spaceModel(practice.homeID)?.tabs.model(practice.sampleID))
        XCTAssertEqual(real.sessionSeed, original)

        practice.leave()
        XCTAssertFalse(practice.browser.family.isOpen)
        XCTAssertTrue(real.family.isOpen)
        XCTAssertEqual(real.sessionSeed, original)
        let fresh = try BrowserOnboardingPractice(shortcuts: shortcuts)
        defer { fresh.leave() }
        XCTAssertFalse(fresh.foundSample)
        XCTAssertFalse(fresh.visitedOtherSpace)
        XCTAssertFalse(fresh.returnedHome)
    }

    func testActualPaletteClientsStayUnusedInPracticeAndShellRoutesCannotNavigateOrChangeAppearance() async throws {
        let server = try BrowserPrivacyHTTPServer()
        server.overrideResponse = { _ in ("200 OK", "Content-Type: application/json\r\n", Data("[]".utf8)) }
        try await server.start()
        let oldFixture = ProcessInfo.processInfo.environment[BrowserNetworkFixture.environmentKey]
        setenv(BrowserNetworkFixture.environmentKey, "http://127.0.0.1:\(server.port)", 1)
        defer {
            if let oldFixture {
                setenv(BrowserNetworkFixture.environmentKey, oldFixture, 1)
            } else {
                unsetenv(BrowserNetworkFixture.environmentKey)
            }
            server.stop()
        }
        let suggestions = BrowserSearchSuggestionClient()
        let web = BrowserWebAnswerClient()
        let lookup = PaletteWebLookup(
            topic: "Ada Lovelace", searchAddress: "https://en.wikipedia.org/search?q=Ada",
            summaryTemplate: "https://en.wikipedia.org/summary/%s",
            imageInfoTemplate: "https://commons.wikimedia.org/%s")
        // Positive controls exercise both real clients through the same local
        // interception. A missing request would otherwise be circular proof.
        _ = try await suggestions.suggestions(from: XCTUnwrap(URL(string: "https://suggest.example/?q=control")))
        _ = await web.summary(for: lookup)
        XCTAssertEqual(server.requests.count, 2)
        let baseline = server.requests.count
        let practice = try BrowserOnboardingPractice(shortcuts: BrowserShortcutStore())
        defer { practice.leave() }
        var preferenceSeed = SessionState.Seed.preview
        for index in preferenceSeed.spaces.indices {
            preferenceSeed.spaces[index].settings.browsingPreferences.followsDefaultSuggestions = false
            preferenceSeed.spaces[index].settings.browsingPreferences.searchSuggestionsEnabled = true
        }
        let preferenceOwner = BrowserStore(seed: preferenceSeed, core: practice.browser.core)
        var enabled = AppPreferences.default
        enabled.palette.sources = enabled.palette.sources.map {
            PaletteSourceChoice(source: $0.source, isEnabled: true, limit: $0.limit)
        }
        try practice.browser.core.send(
            SetAppPreferences(workspaceID: preferenceOwner.family.workspaceID, preferences: enabled))
        let savedPalette = BrowserAppPreferenceStore.shared.palette
        BrowserAppPreferenceStore.shared.palette = enabled.palette
        defer { BrowserAppPreferenceStore.shared.palette = savedPalette }
        for space in practice.browser.spaceModels {
            var preferences = space.settings.browsingPreferences
            preferences.followsDefaultSuggestions = false
            preferences.searchSuggestionsEnabled = true
            practice.browser.updateBrowsingPreferences(preferences, in: space.id)
        }
        var remoteControl = enabled
        remoteControl.palette = remoteControl.palette.offering(.askOde, false)
        try preferenceOwner.core.send(
            SetAppPreferences(workspaceID: preferenceOwner.family.workspaceID, preferences: remoteControl))
        let control = try preferenceOwner.core.query(
            PaletteSuggestions(
                windowID: preferenceOwner.windowID, text: "Ada Lovelace", commands: [], settingsPages: [], remote: [],
                provider: nil, scope: nil, allowsCompletion: true, pasteboard: nil, definition: nil, webSummary: nil,
                spaceID: nil, translation: nil, generative: nil))
        XCTAssertNotNil(control.suggestionAddress)
        XCTAssertNotNil(control.webLookup)
        try preferenceOwner.core.send(
            SetAppPreferences(workspaceID: preferenceOwner.family.workspaceID, preferences: enabled))
        let access = BrowserSpaceAccessController()
        let root = BrowserRootModel(
            browser: practice.browser, pages: practice.pages, chrome: practice.chrome, spaceAccess: access,
            windowState: nil, startupBehavior: .lastActiveTab, persistedSidebarWidth: 260)
        var pasteboardReads = 0
        let model = BrowserCommandPaletteModel(
            browser: practice.browser, space: practice.browser.shownSpace,
            selectedTabID: practice.browser.shownTab?.id, initialQuery: "",
            commands: practice.actions.paletteRegistry(shortcuts: practice.shortcuts),
            lookups: BrowserCommandPaletteLookups(
                suggestionDebounce: .zero,
                fetchSuggestions: { try await suggestions.suggestions(from: $0) },
                lookUpDefinition: { _ in nil }, fetchWebSummary: { await web.summary(for: $0) },
                readPasteboard: {
                    pasteboardReads += 1
                    return "Unrelated clipboard"
                }),
            isSourceAvailable: root.isPaletteSourceAvailable, selectTab: root.selectPaletteTab,
            openURL: { source, url, opening in root.openPaletteURL(url, mode: .newTab, from: source, opening: opening)
            },
            dismiss: practice.chrome.dismissCommandPalette)
        for query in ["an unfamiliar search query", "Ada Lovelace", "wikipedia Ada Lovelace"] {
            model.query = query
            await model.waitForPendingResults()
        }
        XCTAssertEqual(server.requests.count, baseline)
        XCTAssertEqual(pasteboardReads, 0)
        let destination = try XCTUnwrap(URL(string: "https://outside.example/"))
        XCTAssertFalse(model.open(destination.absoluteString, where: .here))
        let source = try XCTUnwrap(practice.browser.shownTabAssignment)
        XCTAssertFalse(root.openPaletteURL(destination, mode: .newTab, from: source))
        root.address = destination.absoluteString
        root.submitAddress()
        XCTAssertFalse(practice.pages.navigate(to: destination.absoluteString))
        XCTAssertFalse(practice.pages.load(destination))
        practice.pages.select()
        let page = try XCTUnwrap(practice.pages.activePage)
        XCTAssertFalse(page.corePage.navigate(to: destination.absoluteString))
        XCTAssertFalse(page.corePage.load(destination))
        XCTAssertFalse(page.isDeveloperModeAutomatic)
        let defaults = BrowserChromeAppearancePreference.defaults
        let keys = [
            BrowserChromeAppearancePreference.tabLayoutKey, BrowserChromeAppearancePreference.sidebarOnRightKey,
            BrowserChromeAppearancePreference.sidebarStyleKey,
        ]
        let before = keys.map { defaults.object(forKey: $0) as? NSObject }
        practice.actions.toggleTabLayout()
        practice.actions.toggleSidebarSide()
        practice.actions.toggleIconSidebar()
        root.setSidebarStyle(.icons)
        XCTAssertEqual(keys.map { defaults.object(forKey: $0) as? NSObject }, before)
        XCTAssertFalse(practice.actions.canPerform(.toggleTabLayout))
        XCTAssertNil(practice.browser.openSettings())
        let registry = practice.actions.paletteRegistry(shortcuts: practice.shortcuts)
        XCTAssertTrue(registry.settingsPages.isEmpty)
        XCTAssertFalse(registry.runApplicationAction("settings"))
        XCTAssertFalse(
            practice.browser.spaceModels.flatMap(\.tabs.models).contains { $0.url == destination.absoluteString })

        model.query = "Trail notes"
        await model.waitForPendingResults()
        let row = try XCTUnwrap(model.items.first { $0.row.tabID == practice.sampleID }?.row)
        model.activate(row)
        practice.observe()
        XCTAssertTrue(practice.foundSample)
        XCTAssertEqual(server.requests.count, baseline)
    }

    func testUnassignedPracticeShortcutStillHasItsPointerRoute() throws {
        let shortcuts = BrowserShortcutStore()
        shortcuts.clearShortcut(for: .newTab)
        let practice = try BrowserOnboardingPractice(shortcuts: shortcuts)
        defer { practice.leave() }
        XCTAssertFalse(practice.handle(key("t", modifiers: .command)))
        practice.actions.perform(.newTab)
        XCTAssertTrue(practice.chrome.isCommandPalettePresented)
        XCTAssertFalse(practice.foundSample)
    }

    // MARK: - Actions - Events

    private func key(_ text: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        guard
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: 0)
        else { preconditionFailure("AppKit must create a key event") }
        return event
    }
}
