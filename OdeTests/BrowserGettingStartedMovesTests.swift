import XCTest

@testable import Ode

/// Getting Started's everyday moves say exactly what the Command Bar's
/// written answers say, keep what the person did across launches, and hear
/// about the moves from the features themselves.
@MainActor
final class BrowserGettingStartedMovesTests: XCTestCase {
    func testUnavailableAssistantDoesNotAdvertiseAnUnofferedTabAction() throws {
        let browser = BrowserStore(seed: .preview)
        let catalog = BrowserSearchCatalog(core: browser.core)
        XCTAssertFalse(catalog.providers(of: .assistant).contains { catalog.isEnabled($0) })
        let answer = try browser.core.query(
            PaletteSuggestions(
                windowID: browser.windowID, text: "chatgpt", commands: [], settingsPages: [], remote: [],
                provider: nil, scope: nil, allowsCompletion: false, pasteboard: nil, definition: nil,
                webSummary: nil, spaceID: nil, translation: nil, generative: nil))
        XCTAssertNil(answer.offeredSearch)
        XCTAssertNil(
            BrowserGettingStartedMove.askAI.paletteHint(for: "chatgpt", provider: nil, offer: nil),
            "The guide cannot offer Tab when the real palette cannot enter an assistant.")
    }

    func testProviderExamplesFollowEnabledCatalogShortcutsAndTabPreferenceWithoutEditingThem() throws {
        let browser = BrowserStore(seed: .preview)
        let catalog = BrowserSearchCatalog(core: browser.core)
        let preferences = BrowserAppPreferenceStore.shared.palette
        defer { BrowserAppPreferenceStore.shared.palette = preferences }
        var withTab = preferences
        withTab.searchesSitesWithTab = true
        BrowserAppPreferenceStore.shared.palette = withTab
        XCTAssertNil(BrowserGettingStartedGuideContext(browser: browser).keyword(for: .askAI))
        catalog.setEnabled(.chatGPT, true)
        try catalog.setShortcuts(.chatGPT, ["myassistant"])
        try catalog.setShortcuts(.youTube, ["videos"])
        let context = BrowserGettingStartedGuideContext(browser: browser)
        XCTAssertEqual(context.keyword(for: .askAI), "myassistant")
        XCTAssertEqual(context.keyword(for: .siteSearch), "videos")
        let before = browser.core.state.searchCatalog
        for move in [BrowserGettingStartedMove.askAI, .siteSearch] {
            let keyword = try XCTUnwrap(context.keyword(for: move))
            let answer = try browser.core.query(
                PaletteSuggestions(
                    windowID: browser.windowID, text: keyword, commands: [], settingsPages: [], remote: [],
                    provider: nil, scope: nil, allowsCompletion: false, pasteboard: nil, definition: nil,
                    webSummary: nil, spaceID: nil, translation: nil, generative: nil))
            XCTAssertEqual(answer.offeredSearch?.provider, context.provider(for: move))
            XCTAssertNotNil(move.paletteHint(for: keyword, provider: nil, offer: answer.offeredSearch?.provider))
            XCTAssertNil(move.paletteHint(for: "unrelated task", provider: nil, offer: nil, example: keyword))
        }
        XCTAssertEqual(browser.core.state.searchCatalog, before)
        withTab.searchesSitesWithTab = false
        BrowserAppPreferenceStore.shared.palette = withTab
        XCTAssertNil(BrowserGettingStartedGuideContext(browser: browser).keyword(for: .askAI))
        XCTAssertNil(BrowserGettingStartedGuideContext(browser: browser).keyword(for: .siteSearch))
        XCTAssertTrue(catalog.isEnabled(try XCTUnwrap(catalog.providers.first { $0.builtIn == .chatGPT })))
        XCTAssertEqual(catalog.settings(.chatGPT)?.shortcuts, ["myassistant"])
        withTab.searchesSitesWithTab = true
        BrowserAppPreferenceStore.shared.palette = withTab
        for provider in catalog.providers(of: .website) {
            if let builtIn = provider.builtIn { catalog.setEnabled(builtIn, false) }
        }
        XCTAssertNil(BrowserGettingStartedGuideContext(browser: browser).keyword(for: .siteSearch))
    }

    func testFreshGuideRequiresAnotherSpaceAndUsesOnlyDisposableSplitPractice() throws {
        let space = SpaceState.Seed(name: "Personal", tabs: [.startPage()])
        let browser = BrowserStore(seed: SessionState.Seed(spaces: [space]))
        _ = try XCTUnwrap(browser.openGettingStarted())
        let before = browser.sessionSeed
        let context = BrowserGettingStartedGuideContext(browser: browser)
        XCTAssertFalse(context.hasOtherSpace)
        XCTAssertFalse(context.canSplit)
        let practice = BrowserGettingStartedPractice()
        practice.makeSplit()
        XCTAssertEqual(practice.members.count, 2)
        XCTAssertEqual(browser.sessionSeed, before)
        XCTAssertNil(browser.selectAdjacentSpace(.next))
    }

    func testEachMoveUsesItsAnswerCardsWordsAndKeys() throws {
        let answers = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "OdeCore/src/OdeCore/Domain/Answers/answers.json")
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: answers)) as? [String: Any])
        let cards = try XCTUnwrap(document["cards"] as? [[String: Any]])
        let byID = Dictionary(
            uniqueKeysWithValues: cards.compactMap { card in (card["id"] as? String).map { ($0, card) } })

        XCTAssertEqual(BrowserGettingStartedMove.allCases.count, 7)
        for move in BrowserGettingStartedMove.allCases {
            let card = try XCTUnwrap(byID[move.answerID], "No answer card \(move.answerID)")
            XCTAssertEqual(card["status"] as? String, "live", move.answerID)
            XCTAssertEqual(move.title, card["title"] as? String, move.answerID)
            XCTAssertEqual(move.steps, card["steps"] as? [String], move.answerID)
            XCTAssertEqual(move.keys, card["keys"] as? String, move.answerID)
        }
    }

    func testShowMeRunsOnlyCommandsThatStartTheMove() {
        XCTAssertEqual(BrowserGettingStartedMove.commandBar.demonstration, .newTab)
        XCTAssertEqual(BrowserGettingStartedMove.splitView.demonstration, .splitWithNextTab)
        XCTAssertEqual(BrowserGettingStartedMove.switchSpace.demonstration, .nextSpace)
        XCTAssertNil(BrowserGettingStartedMove.peek.demonstration, "Peek needs a link on a page.")
        XCTAssertNil(BrowserGettingStartedMove.boost.demonstration, "A Boost needs a website on screen.")
    }

    func testMovesAreKeptAcrossLaunchesAndStartOver() throws {
        let suite = "GettingStartedMovesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let moves = BrowserGettingStartedMoves(defaults: defaults)
        XCTAssertEqual(moves.next, .commandBar)
        moves.record(.commandBar)
        moves.record(.peek)
        moves.record(.peek)
        XCTAssertEqual(moves.next, .siteSearch)

        let relaunched = BrowserGettingStartedMoves(defaults: defaults)
        XCTAssertEqual(relaunched.done, [.commandBar, .peek])

        relaunched.reset()
        XCTAssertTrue(BrowserGettingStartedMoves(defaults: defaults).done.isEmpty)
    }

    func testTheCommandBarReportsASiteOrAnAssistantEnteredWithTab() throws {
        let previous = BrowserGettingStartedMoves.current
        defer { BrowserGettingStartedMoves.current = previous }
        let moves = BrowserGettingStartedMoves(defaults: nil)
        BrowserGettingStartedMoves.current = moves

        BrowserGettingStartedMoves.record(.siteSearch)
        XCTAssertEqual(moves.done, [.siteSearch])
        BrowserGettingStartedMoves.current = nil
        BrowserGettingStartedMoves.record(.askAI)
        XCTAssertEqual(moves.done, [.siteSearch], "Without a launch record nothing is kept.")
    }
}
