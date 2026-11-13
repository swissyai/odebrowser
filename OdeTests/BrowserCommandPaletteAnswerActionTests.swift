import XCTest

@testable import Ode

/// Every written answer's "Do it" names something this Mac app can open or
/// run: a settings page by its settings name, a page of a Space's settings,
/// or an application menu action. The core checks the commands; the names
/// below belong to the app, so a renamed page or action fails here instead of
/// leaving a button that does nothing.
@MainActor
final class BrowserCommandPaletteAnswerActionTests: XCTestCase {
    func testUnsupportedCuratedActionsKeepTheirGuideWithoutDispatchOrDismissal() async throws {
        for action in [
            AnswerAction(command: .newTab), AnswerAction(settingsPage: "general"),
            AnswerAction(spacePage: "privacy"), AnswerAction(applicationAction: "settings"),
        ] {
            var dispatches = 0
            var dismissals = 0
            var guides = 0
            let registry = BrowserCommandPaletteCommandRegistry(commands: [], perform: { _ in dispatches += 1 })
            let model = makeModel(
                action: action, registry: registry, openGuide: { guides += 1 }, dismiss: { dismissals += 1 })
            await model.waitForPendingResults()
            let item = try XCTUnwrap(model.items.first { $0.row.answer != nil })
            var coreDispatches = 0
            model.browser.core.batchApplied = { _ in coreDispatches += 1 }
            XCTAssertEqual(model.answerControl(for: item), .readMore)

            model.run(.doIt, of: item)
            XCTAssertEqual(model.performAnswerAction(of: try XCTUnwrap(item.row.answer)), .unsupported)
            XCTAssertEqual(dispatches, 0)
            XCTAssertEqual(dismissals, 0)
            XCTAssertEqual(guides, 0, "A stale Do It click must not turn into Read More")
            XCTAssertEqual(coreDispatches, 0, "Unsupported actions must not record a palette choice")

            model.run(.readMore, of: item)
            XCTAssertEqual(guides, 1)
            XCTAssertEqual(dismissals, 1)
            XCTAssertEqual(coreDispatches, 1, "The successful guide opening records its choice once")
            model.browser.core.batchApplied = nil
            model.stop()
        }
    }

    func testUnsupportedOrdinaryCommandAndSettingsRowsDoNotRecordOrDismiss() async throws {
        for (kind, action) in [
            (PaletteRowKind.command, AnswerAction(command: .reloadPage)),
            (PaletteRowKind.settingsPage, AnswerAction(settingsPage: "general")),
        ] {
            var dispatches = 0
            var dismissals = 0
            let registry = BrowserCommandPaletteCommandRegistry(commands: [], perform: { _ in dispatches += 1 })
            let model = makeModel(
                action: action, registry: registry, rowKind: kind, dismiss: { dismissals += 1 })
            await model.waitForPendingResults()
            let item = try XCTUnwrap(model.items.first)
            var coreDispatches = 0
            model.browser.core.batchApplied = { _ in coreDispatches += 1 }
            model.activate(item.row)
            XCTAssertEqual(dispatches, 0)
            XCTAssertEqual(coreDispatches, 0)
            XCTAssertEqual(dismissals, 0)
            model.browser.core.batchApplied = nil
            model.stop()
        }
    }

    func testSupportedCuratedCommandRunsOnceAndLostSourceCannotRunIt() async throws {
        var available = true
        var dispatches: [ShortcutCommand] = []
        var dismissals = 0
        let registry = BrowserCommandPaletteCommandRegistry(
            commands: [.reloadPage], perform: { dispatches.append($0) })
        let model = makeModel(
            action: AnswerAction(command: .reloadPage), registry: registry,
            sourceAvailable: { available }, dismiss: { dismissals += 1 })
        await model.waitForPendingResults()
        let item = try XCTUnwrap(model.items.first { $0.row.answer != nil })
        XCTAssertEqual(model.answerControl(for: item), .doIt)
        var coreDispatches = 0
        model.browser.core.batchApplied = { _ in coreDispatches += 1 }

        available = false
        model.run(.doIt, of: item)
        XCTAssertTrue(dispatches.isEmpty)
        XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(coreDispatches, 0)

        available = true
        model.run(.doIt, of: item)
        XCTAssertEqual(dispatches, [.reloadPage])
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(coreDispatches, 1)
        model.browser.core.batchApplied = nil
        model.stop()
    }

    func testRevokedCapabilityAndDeclinedSettingsDoNotRecordOrDismiss() async throws {
        var available = true
        var dispatches = 0
        var dismissals = 0
        let registry = BrowserCommandPaletteCommandRegistry(
            commands: [.reloadPage],
            settingsPages: [PaletteSettingsPage(name: "general", title: "General", terms: "")],
            dispatch: { _ in
                dispatches += 1
                return .performed
            }, canPerform: { _ in available },
            openSettings: { _ in
                dispatches += 1
                return false
            })
        let command = makeModel(
            action: AnswerAction(command: .reloadPage), registry: registry, dismiss: { dismissals += 1 })
        await command.waitForPendingResults()
        let commandItem = try XCTUnwrap(command.items.first { $0.row.answer != nil })
        XCTAssertEqual(command.answerControl(for: commandItem), .doIt)
        var coreDispatches = 0
        command.browser.core.batchApplied = { _ in coreDispatches += 1 }
        available = false
        command.run(.doIt, of: commandItem)
        XCTAssertEqual(command.answerControl(for: commandItem), .readMore)
        XCTAssertEqual(dispatches, 0)
        XCTAssertEqual(coreDispatches, 0)
        XCTAssertEqual(dismissals, 0)
        command.browser.core.batchApplied = nil
        command.stop()

        let settings = makeModel(
            action: AnswerAction(settingsPage: "general"), registry: registry, dismiss: { dismissals += 1 })
        await settings.waitForPendingResults()
        let settingsItem = try XCTUnwrap(settings.items.first { $0.row.answer != nil })
        XCTAssertEqual(settings.answerControl(for: settingsItem), .doIt)
        settings.browser.core.batchApplied = { _ in coreDispatches += 1 }
        settings.run(.doIt, of: settingsItem)
        XCTAssertEqual(dispatches, 1, "The supplied opener is called exactly once, and may decline")
        XCTAssertEqual(coreDispatches, 0)
        XCTAssertEqual(dismissals, 0)
        settings.browser.core.batchApplied = nil
        settings.stop()
    }

    func testSupportedNamedActionsDispatchAndRecordExactlyOnce() async throws {
        var opened: [String] = []
        let registry = BrowserCommandPaletteCommandRegistry(
            commands: [], settingsPages: [PaletteSettingsPage(name: "general", title: "General", terms: "")],
            openSettings: {
                opened.append($0)
                return true
            },
            spaceSettingsPages: ["privacy"],
            openSpaceSettings: {
                opened.append($0)
                return true
            },
            applicationActions: ["settings"],
            runApplicationAction: {
                opened.append($0)
                return true
            })
        for action in [
            AnswerAction(settingsPage: "general"), AnswerAction(spacePage: "privacy"),
            AnswerAction(applicationAction: "settings"),
        ] {
            var dismissals = 0
            let model = makeModel(action: action, registry: registry, dismiss: { dismissals += 1 })
            await model.waitForPendingResults()
            let item = try XCTUnwrap(model.items.first { $0.row.answer != nil })
            XCTAssertEqual(model.answerControl(for: item), .doIt)
            var coreDispatches = 0
            model.browser.core.batchApplied = { _ in coreDispatches += 1 }
            let before = opened.count
            model.run(.doIt, of: item)
            XCTAssertEqual(opened.count, before + 1)
            XCTAssertEqual(coreDispatches, 1)
            XCTAssertEqual(dismissals, 1)
            model.browser.core.batchApplied = nil
            model.stop()
        }
        XCTAssertEqual(opened, ["general", "privacy", "settings"])
    }

    func testStaleAnswerItemCannotDispatchAfterEditing() async throws {
        var dispatches = 0
        let registry = BrowserCommandPaletteCommandRegistry(
            commands: [.reloadPage], perform: { _ in dispatches += 1 })
        let model = makeModel(action: AnswerAction(command: .reloadPage), registry: registry, dismiss: {})
        await model.waitForPendingResults()
        let item = try XCTUnwrap(model.items.first { $0.row.answer != nil })
        model.query = "another query"
        model.run(.doIt, of: item)
        XCTAssertEqual(dispatches, 0)
        model.stop()
    }

    func testNativeFreshCommandBarSurvivesCompletionOfTheOldAnswer() async throws {
        let browser = BrowserStore(seed: .preview)
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        let chrome = BrowserChromeState()
        let actions = BrowserCommandActions(browser: browser, pages: pages, chrome: chrome, windows: nil)
        let registry = actions.paletteRegistry(shortcuts: nil)
        XCTAssertTrue(registry.supports(AnswerAction(command: .newTab)))
        XCTAssertFalse(registry.commands.contains(.newTab), "Native support is distinct from ranked command rows")
        for _ in 0..<2 {
            chrome.openLocation("https://old.example.test/")
            let model = makeModel(
                action: AnswerAction(command: .newTab), registry: registry,
                browser: browser, dismiss: chrome.dismissCommandPalette)
            await model.waitForPendingResults()
            let item = try XCTUnwrap(model.items.first { $0.row.answer != nil })
            XCTAssertEqual(model.answerControl(for: item), .doIt)
            model.run(.doIt, of: item)
            XCTAssertEqual(chrome.commandPaletteMode, .newTab, "Old completion must not dismiss the new palette")
            chrome.openLocation("https://new.example.test/")
            model.run(.doIt, of: item)
            XCTAssertTrue(chrome.isEditingLocation, "The completed old model must not dispatch again")
            model.stop()
        }
    }

    func testEmbeddedStartPageRemainsUsableAfterNativeOpenLocation() async throws {
        let source = TabState.Seed.startPage()
        let space = SpaceState.Seed(name: "Embedded", symbol: "command", accent: .indigo, folders: [], tabs: [source])
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: source.id])
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        let chrome = BrowserChromeState()
        let actions = BrowserCommandActions(browser: browser, pages: pages, chrome: chrome, windows: nil)
        let core = browser.core
        var opened: [URL] = []
        var dismissals = 0
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.shownSpace, selectedTabID: source.id,
            initialQuery: "", commands: actions.paletteRegistry(shortcuts: nil), offersRestingCommands: false,
            presentation: .embedded,
            lookups: BrowserCommandPaletteLookups(
                fetchSuggestions: { _ in [] }, lookUpDefinition: { _ in nil }, fetchWebSummary: { _ in nil },
                answer: { question in
                    // A late provider may return even after its caller is cancelled.
                    await Task.detached { try? await Task.sleep(for: .milliseconds(60)) }.value
                    return try? core.query(question)
                }),
            isSourceAvailable: { browser.shownTab?.id == $0.tabID }, selectTab: { _, _ in false },
            openURL: { _, url, _ in
                opened.append(url)
                return true
            }, dismiss: { dismissals += 1 })
        defer { model.stop() }
        let question = "edit url"
        model.updateCompletionEditing(
            text: question, selection: NSRange(location: question.utf16.count, length: 0), isComposing: false)
        await model.waitForPendingResults()
        let item = try XCTUnwrap(model.items.first { $0.row.answer?.action?.command == .openLocation })
        let focusRequest = chrome.startPageFocusRequest
        model.run(.doIt, of: item)
        XCTAssertTrue(chrome.isEditingLocation)
        XCTAssertEqual(browser.shownTab?.id, source.id)
        XCTAssertEqual(chrome.startPageFocusRequest, focusRequest, "The embedded presentation has not been replaced")
        XCTAssertEqual(dismissals, 0)
        model.run(.doIt, of: item)
        model.activate(item.row)
        XCTAssertTrue(chrome.isEditingLocation, "Old button and row callbacks cannot toggle the overlay again")
        chrome.dismissCommandPalette()

        let superseded = "https://superseded.example.test/"
        model.updateCompletionEditing(
            text: superseded, selection: NSRange(location: superseded.utf16.count, length: 0), isComposing: false)
        model.pressReturn()
        await Task.yield()
        let resumed = "https://resumed.example.test/"
        model.updateCompletionEditing(
            text: resumed, selection: NSRange(location: resumed.utf16.count, length: 0), isComposing: false)
        model.run(.doIt, of: item)
        await model.waitForPendingResults()
        XCTAssertFalse(chrome.isCommandPalettePresented, "The old answer callback must not reopen the overlay")
        XCTAssertTrue(opened.isEmpty, "A delayed Return belongs only to the superseded input")
        model.pressReturn()
        XCTAssertEqual(opened.map(\.absoluteString), ["https://resumed.example.test/"])
        XCTAssertEqual(dismissals, 1)
    }

    func testMacNamedSettingsRequireAPresentationOwnerAndRouteOnlyAfterOpening() throws {
        let browser = BrowserStore(seed: .preview)
        let root = makeRoot(browser: browser)
        let general = AnswerAction(settingsPage: BrowserSettingsDestination.general.name)
        let privacy = AnswerAction(spacePage: BrowserSpaceSettingsTab.privacy.name)
        let sourceID = browser.shownTab?.id
        let withoutOwner = root.paletteRegistry(windows: nil, layoutDirection: .leftToRight, shortcuts: nil)
        XCTAssertFalse(withoutOwner.supports(general))
        XCTAssertFalse(withoutOwner.supports(privacy))
        XCTAssertEqual(withoutOwner.perform(general), .unsupported)
        XCTAssertFalse(root.openPaletteSpaceSettings(BrowserSpaceSettingsTab.privacy.name, in: nil))
        XCTAssertEqual(browser.shownTab?.id, sourceID)

        let presentation = BrowserSpaceSettingsPresentationState()
        let registry = root.paletteRegistry(
            windows: nil, layoutDirection: .leftToRight, shortcuts: nil, settings: presentation)
        XCTAssertEqual(registry.perform(general), .performed)
        XCTAssertEqual(browser.shownTab?.nativeTabContent, .settings)
        XCTAssertEqual(presentation.requestedSpaceID, browser.shownSpace?.id)
        let route = BrowserSettingsTabState()
        presentation.request.apply(to: route, spaceID: presentation.requestedSpaceID)
        XCTAssertEqual(route.navigation.selection, .destination(.general))
        XCTAssertEqual(registry.perform(privacy), .performed)
        presentation.request.apply(to: route, spaceID: presentation.requestedSpaceID)
        XCTAssertEqual(route.navigation.selection, browser.shownSpace.map { .space($0.id) })
        XCTAssertEqual(route.spaceTab, .privacy)

        let practice = try BrowserOnboardingPractice(shortcuts: BrowserShortcutStore())
        defer { practice.leave() }
        let practiceRoot = makeRoot(browser: practice.browser)
        let revision = presentation.revision
        let requestedAssignment = presentation.requestedAssignment
        XCTAssertFalse(practiceRoot.openPaletteSettings(BrowserSettingsDestination.general.name, in: presentation))
        XCTAssertFalse(practiceRoot.openPaletteSpaceSettings(BrowserSpaceSettingsTab.privacy.name, in: presentation))
        XCTAssertEqual(presentation.revision, revision, "Refused core opens must not leave a pending settings route")
        XCTAssertEqual(presentation.requestedAssignment, requestedAssignment)
    }

    // MARK: - Actions - Catalog

    func testEveryAnswerOpensASettingsPageSpacePageOrMenuActionTheAppHas() throws {
        let answers = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "OdeCore/src/OdeCore/Domain/Answers/answers.json")
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: answers)) as? [String: Any])
        let cards = try XCTUnwrap(document["cards"] as? [[String: Any]])
        let settings = Set(BrowserSettingsDestination.all.map(\.name))
        let spacePages = Set(BrowserSpaceSettingsTab.all.map(\.name))
        let menuActions = Set(BrowserMacApplicationAction.all.map(\.name))
        var named = 0

        for card in cards {
            guard let action = card["action"] as? [String: String] else { continue }
            let id = card["id"] as? String ?? "?"
            if let page = action["settings"] {
                XCTAssertTrue(settings.contains(page), "\(id) opens no settings page \(page)")
            }
            if let page = action["space"] {
                XCTAssertTrue(spacePages.contains(page), "\(id) opens no Space page \(page)")
            }
            if let name = action["app"] {
                XCTAssertTrue(menuActions.contains(name), "\(id) runs no menu action \(name)")
            }
            named += action.keys.filter { $0 != "command" }.count
        }
        XCTAssertGreaterThan(named, 50)
    }

    // MARK: - Actions - Fixtures

    private func makeRoot(browser: BrowserStore) -> BrowserRootModel {
        BrowserRootModel(
            browser: browser, pages: BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true),
            chrome: BrowserChromeState(), spaceAccess: BrowserSpaceAccessController(), windowState: nil,
            startupBehavior: .lastActiveTab, persistedSidebarWidth: 260)
    }

    private func makeModel(
        action: AnswerAction, registry: BrowserCommandPaletteCommandRegistry,
        browser: BrowserStore? = nil, rowKind: PaletteRowKind = .answer,
        sourceAvailable: @escaping () -> Bool = { true },
        openGuide: @escaping () -> Void = {}, dismiss: @escaping () -> Void
    ) -> BrowserCommandPaletteModel {
        let browser = browser ?? BrowserStore(seed: .preview)
        let card = AnswerCard(
            id: "action-fixture", kind: .task, title: "Action", steps: ["Run the action"],
            action: action, guide: "https://example.test/guide")
        let row = PaletteRow(
            kind: rowKind, title: card.title, subtitle: "", symbol: "questionmark.circle",
            subjectID: nil, tabID: nil, address: nil, command: action.command, provider: nil,
            settingsPage: action.settingsPage, scope: nil, reason: nil,
            answer: rowKind == .answer ? card : nil, topResult: nil, card: nil, emphasis: nil)
        let answer = PaletteAnswer(
            groups: [PaletteGroup(section: .answer, rows: [row])], completion: nil, suggestionAddress: nil,
            offeredSearch: nil, offeredScope: nil, matchingProviders: [], entry: nil, definitionTerm: nil,
            webLookup: nil, translationLookup: nil, generativeLookup: nil, keepsQueryPrivate: false)
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.shownSpace, selectedTabID: browser.shownTab?.id,
            initialQuery: "", commands: registry,
            lookups: BrowserCommandPaletteLookups(answer: { _ in answer }),
            isSourceAvailable: { _ in sourceAvailable() }, selectTab: { _, _ in false },
            openURL: { _, _, _ in
                openGuide()
                return true
            }, dismiss: dismiss)
        model.query = "action fixture"
        return model
    }
}
