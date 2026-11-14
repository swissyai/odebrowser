import Foundation
import XCTest

@testable import Ode

/// A short answer below the search: a conversion the core works out, and a
/// definition the palette asks the device's dictionary for and shows without
/// moving the selected row; Return on a definition opens the dictionary.
@MainActor
final class BrowserCommandPaletteCardTests: XCTestCase {
    func testLocalCalculationsDoNotAskOptedInRemoteClients() async throws {
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
        var seed = SessionState.Seed.preview
        for index in seed.spaces.indices {
            seed.spaces[index].settings.browsingPreferences.followsDefaultSuggestions = false
            seed.spaces[index].settings.browsingPreferences.searchSuggestionsEnabled = true
        }
        let browser = BrowserStore(seed: seed)
        var preferences = AppPreferences.default
        preferences.palette.sources = preferences.palette.sources.map {
            PaletteSourceChoice(source: $0.source, isEnabled: true, limit: $0.limit)
        }
        try browser.core.send(SetAppPreferences(workspaceID: browser.family.workspaceID, preferences: preferences))
        let suggestions = BrowserSearchSuggestionClient()
        let web = BrowserWebAnswerClient()
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.shownSpace, selectedTabID: browser.shownTab?.id, initialQuery: "",
            commands: nil,
            lookups: BrowserCommandPaletteLookups(
                suggestionDebounce: .zero,
                fetchSuggestions: { try await suggestions.suggestions(from: $0) }, isOnline: { true },
                lookUpDefinition: { _ in nil }, fetchWebSummary: { await web.summary(for: $0) },
                readPasteboard: { nil }),
            isSourceAvailable: { _ in true }, selectTab: { _, _ in false }, openURL: { _, _, _ in false }, dismiss: {})

        // The production model must actually reach both clients through the
        // loopback fixture before a lack of arithmetic requests proves anything.
        model.query = "Ada Lovelace"
        await model.waitForPendingResults()
        XCTAssertTrue(server.requests.contains { $0.path.hasPrefix("/www.google.com/") })
        XCTAssertTrue(server.requests.contains { $0.path.contains("en.wikipedia.org") })
        let before = server.requests.count
        for (query, expected) in [("1e3+2", "1002"), ("20% of 80", "16"), ("20% off 80", "64")] {
            model.query = query
            await model.waitForPendingResults()
            let card = try XCTUnwrap(model.items.first { $0.row.card?.kind == .calculation }?.row.card)
            XCTAssertEqual(BrowserCommandPaletteCardText.copied(card), expected)
            XCTAssertEqual(model.items.first?.row.kind, .search)
            XCTAssertEqual(server.requests.count, before, query)
        }
    }

    func testAConversionShowsBelowTheSearchAndTheSearchStaysSelected() async throws {
        let (model, _) = makeModel(definition: nil)
        model.query = "5 km in miles"
        await model.waitForPendingResults()

        XCTAssertEqual(model.items.first?.row.kind, .search)
        XCTAssertEqual(model.selectedResultIndex, 0)
        let card = try XCTUnwrap(model.items.first { $0.row.kind == .card }?.row.card)
        XCTAssertEqual(card.kind, .conversion)
        XCTAssertEqual(BrowserCommandPaletteCardText.copied(card), "3.107")
    }

    func testPredictiveConversionsKeepDistinctRowsAndReturnCopiesEachSelectedCardsOwnValue() async throws {
        for text in ["how many oz in a", "how many cm in 0"] {
            var copied: [String] = []
            let commands = BrowserCommandPaletteCommandRegistry(
                commands: [], perform: { _ in }, copy: { copied.append($0) })
            let (model, _) = makeModel(definition: nil, commands: commands)
            model.query = text
            await model.waitForPendingResults()
            let cards = model.items.filter { $0.row.card?.kind == .conversion }

            XCTAssertEqual(model.selectedResultIndex, 0)
            XCTAssertEqual(model.items.first?.row.kind, .search)
            XCTAssertGreaterThanOrEqual(cards.count, 2)
            XCTAssertLessThanOrEqual(cards.count, 4)
            XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
            for item in cards {
                let value = try XCTUnwrap(item.row.card?.value)
                model.selectResult(at: item.index)
                model.pressReturn()
                XCTAssertEqual(copied.last, value)
            }
            XCTAssertEqual(copied, cards.compactMap { $0.row.card?.value })
        }
    }

    func testTabCopiesReadyAnswerFromDefaultSearchWithoutChangingReturnsTarget() async throws {
        var copied: [String] = []
        let commands = BrowserCommandPaletteCommandRegistry(
            commands: [], perform: { _ in }, copy: { copied.append($0) })
        let (model, shown) = makeModel(definition: nil, commands: commands)
        defer { model.stop() }
        model.isFieldFocused = true
        model.query = "5 km in miles"
        await model.waitForPendingResults()
        let candidate = try XCTUnwrap(model.tabCopyCandidate)

        model.pressTab()

        XCTAssertEqual(copied, [candidate.row.card?.value].compactMap { $0 })
        XCTAssertEqual(model.selectedResultIndex, 0)
        XCTAssertTrue(model.isCopied(candidate))
        XCTAssertEqual(shown.dismissals, 0)
        model.pressReturn()
        XCTAssertEqual(shown.opened.count, 1, "Return still runs the primary web search")
        XCTAssertEqual(copied.count, 1)
        XCTAssertNil(model.copiedCardID)
    }

    func testAmbiguousAnswersRequireAnExplicitSelectedCardForTabCopy() async throws {
        var copied: [String] = []
        let commands = BrowserCommandPaletteCommandRegistry(
            commands: [], perform: { _ in }, copy: { copied.append($0) })
        let (model, shown) = makeModel(definition: nil, commands: commands)
        defer { model.stop() }
        model.isFieldFocused = true
        model.query = "how many oz in a"
        await model.waitForPendingResults()
        let cards = model.items.filter { model.canCopyCard($0) }
        XCTAssertGreaterThan(cards.count, 1)
        XCTAssertNil(model.tabCopyCandidate)
        let selected = try XCTUnwrap(cards.last)
        model.selectResult(at: selected.index)

        model.pressTab()

        XCTAssertEqual(copied, [selected.row.card?.value].compactMap { $0 })
        XCTAssertEqual(model.selectedResultIndex, selected.index)
        XCTAssertEqual(shown.dismissals, 0)
    }

    func testTabNeverCopiesAResultThatArrivesAfterTheKeyOrAfterAnotherEdit() async throws {
        var copied: [String] = []
        let commands = BrowserCommandPaletteCommandRegistry(
            commands: [], perform: { _ in }, copy: { copied.append($0) })
        let (model, _) = makeModel(definition: nil, commands: commands)
        defer { model.stop() }
        model.isFieldFocused = true
        model.query = "5 km in miles"
        model.pressTab()
        await model.waitForPendingResults()
        XCTAssertTrue(copied.isEmpty)
        let old = try XCTUnwrap(model.items.first { model.canCopyCard($0) })
        model.query = "20% of 80"
        model.copyCard(old)
        model.pressTab()
        await model.waitForPendingResults()
        XCTAssertTrue(copied.isEmpty)
        XCTAssertNil(model.copiedCardID)
    }

    func testCopyRevalidatesFocusSourceAndPresentationWithoutStealingFocus() async throws {
        var copied: [String] = []
        let commands = BrowserCommandPaletteCommandRegistry(
            commands: [], perform: { _ in }, copy: { copied.append($0) })
        let (model, shown) = makeModel(definition: nil, commands: commands)
        defer { model.stop() }
        model.query = "5 km in miles"
        await model.waitForPendingResults()
        let card = try XCTUnwrap(model.items.first { model.canCopyCard($0) })
        XCTAssertNil(model.tabCopyCandidate, "No hardware offer outside the field")
        model.copyCard(card)
        XCTAssertFalse(model.isFieldFocused, "A touch or accessibility Copy must not move focus")
        XCTAssertTrue(model.isCopied(card))
        shown.sourceAvailable = false
        model.copyCard(card)
        XCTAssertFalse(model.isCopied(card))
        XCTAssertEqual(copied.count, 1)
        model.sourceAvailabilityChanged(false)
        XCTAssertNil(model.copiedCardID)
        shown.sourceAvailable = true
        model.sourceAvailabilityChanged(true)
        await model.waitForPendingResults()
        let current = try XCTUnwrap(model.items.first { model.canCopyCard($0) })
        model.dismiss()
        model.copyCard(current)
        XCTAssertEqual(copied.count, 1)
        XCTAssertNil(model.copiedCardID)
    }

    func testUnavailableOrRefusedCopyDoesNotReportSuccess() async throws {
        let registries: [BrowserCommandPaletteCommandRegistry?] = [
            nil,
            BrowserCommandPaletteCommandRegistry(commands: [], perform: { _ in }),
            BrowserCommandPaletteCommandRegistry(commands: [], perform: { _ in }, copyInline: { _ in false }),
        ]
        for commands in registries {
            let (model, _) = makeModel(definition: nil, commands: commands)
            model.query = "5 km in miles"
            await model.waitForPendingResults()
            let card = try XCTUnwrap(model.items.first { $0.row.card?.kind == .conversion })
            model.copyCard(card)
            XCTAssertNil(model.copiedCardID)
            model.stop()
        }
    }

    func testADefinitionFromTheDictionaryJoinsWithoutMovingTheSelection() async throws {
        let entry = "e·phem·er·al | əˈfem(ə)rəl | adjective lasting for a very short time."
        let (model, shown) = makeModel(definition: PaletteDefinition(term: "ephemeral", text: entry))
        model.query = "define ephemeral"
        await model.waitForPendingResults()

        XCTAssertEqual(model.selectedResultIndex, 0)
        let item = try XCTUnwrap(model.items.first { $0.row.kind == .card })
        XCTAssertEqual(item.row.card?.title, "e·phem·er·al")
        XCTAssertNil(model.shiftReturnOpening(for: item.row))

        model.activate(item.row)
        XCTAssertEqual(shown.terms, ["ephemeral"])
    }

    func testATimeCardWritesTheTimeInItsZone() {
        let instant = Date(timeIntervalSince1970: 1_793_000_000)
        let clock = PaletteCardClock(
            instant: instant, zone: "Asia/Tokyo", place: "Tokyo", fromZone: "America/New_York", fromPlace: "New York",
            difference: "14 hours ahead")
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let hour = tokyo.component(.hour, from: instant)
        XCTAssertTrue(
            BrowserCommandPaletteCardText.time(clock).contains("\(hour % 12 == 0 ? 12 : hour % 12)")
                || BrowserCommandPaletteCardText.time(clock).contains("\(hour)"))
        XCTAssertNotNil(BrowserCommandPaletteCardText.given(clock))
    }

    func testAnEncyclopediaSummaryShowsOnlyOnceWebAnswersAreOn() async throws {
        let summary = PaletteWebSummary(
            title: "Albert Einstein", type: "standard", description: "German-born theoretical physicist",
            extract: "Albert Einstein was a German-born theoretical physicist.",
            page: "https://en.wikipedia.org/wiki/Albert_Einstein",
            thumbnail: nil, imageArtist: nil, imageLicense: nil)
        let asked = Asked()
        let (model, _) = makeModel(definition: nil, summary: summary, asked: asked)
        model.query = "albert einstein"
        await model.waitForPendingResults()
        XCTAssertTrue(asked.topics.isEmpty, "Web answers start off, so nothing is asked.")
        XCTAssertFalse(model.items.contains { $0.row.kind == .card })

        var preferences = model.browser.workspaceModel?.appPreferences ?? .default
        preferences.palette.sources = preferences.palette.sources.map {
            $0.source == .webAnswers ? PaletteSourceChoice(source: $0.source, isEnabled: true, limit: $0.limit) : $0
        }
        XCTAssertTrue(
            model.browser.sendAppPreferences(
                SetAppPreferences(workspaceID: model.browser.family.workspaceID, preferences: preferences)))
        model.query = "Albert Einstein"
        await model.waitForPendingResults()

        XCTAssertEqual(asked.topics, ["Albert Einstein"])
        XCTAssertEqual(model.selectedResultIndex, 0)
        let card = try XCTUnwrap(model.items.first { $0.row.kind == .card }?.row.card)
        XCTAssertEqual(card.kind, .encyclopedia)
        XCTAssertEqual(card.address, "https://en.wikipedia.org/wiki/Albert_Einstein")
        XCTAssertEqual(card.credit, "Wikipedia")
    }

    // MARK: - Fixtures

    private final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        var topics: [String] { lock.withLock { asked } }
        func record(_ topic: String) { lock.withLock { asked.append(topic) } }
    }

    private final class Shown {
        var terms: [String] = []
        var opened: [URL] = []
        var dismissals = 0
        var sourceAvailable = true
    }

    private func makeModel(
        definition: PaletteDefinition?, summary: PaletteWebSummary? = nil, asked: Asked = Asked(),
        commands: BrowserCommandPaletteCommandRegistry? = nil
    ) -> (BrowserCommandPaletteModel, Shown) {
        let source = TabState.Seed.startPage(id: UUID(), lastActivatedAt: Date(timeIntervalSinceReferenceDate: 600))
        let space = SpaceState.Seed(
            id: UUID(), profileID: UUID(), name: "Cards", symbol: "text.bubble", accent: .indigo, folders: [],
            tabs: [source])
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: source.id])
        let shown = Shown()
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: source.id, initialQuery: "",
            commands: commands,
            lookups: BrowserCommandPaletteLookups(
                suggestionDebounce: .zero, fetchSuggestions: { _ in [] }, isOnline: { true },
                lookUpDefinition: { term in definition?.term == term ? definition : nil },
                showInDictionary: { term in
                    shown.terms.append(term)
                    return true
                },
                fetchWebSummary: { lookup in
                    asked.record(lookup.topic)
                    return summary
                }),
            isSourceAvailable: { _ in shown.sourceAvailable }, selectTab: { _, _ in false },
            openURL: { _, url, _ in
                shown.opened.append(url)
                return true
            }, dismiss: { shown.dismissals += 1 },
            openings: BrowserCommandPaletteOpening.all)
        return (model, shown)
    }
}
