import SwiftUI
import XCTest

@testable import Ode

/// The Command Bar's look: the bloom Tab sets off when it enters a provider,
/// the accessibility settings that drop the blur, the site a completion
/// opens, the one-line rows with a page's domain after its title, and the
/// parts of a title the core marked for what was typed.
@MainActor
final class BrowserCommandPaletteLookTests: XCTestCase {
    func testTheBloomSwellsQuicklyThenFadesAwayWithinTwoThirdsOfASecond() {
        let duration = KeyframeTimeline(initialValue: BrowserSearchProviderBloom.Frame.rest) {
            BrowserSearchProviderBloom.keyframes
        }.duration
        XCTAssertEqual(duration, BrowserSearchProviderBloom.duration, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(duration, 0.6)
        XCTAssertLessThanOrEqual(duration, 0.7)

        let start = BrowserSearchProviderBloom.frame(at: 0)
        let early = BrowserSearchProviderBloom.frame(at: 0.05)
        let peak = BrowserSearchProviderBloom.frame(at: 0.15)
        let fading = BrowserSearchProviderBloom.frame(at: 0.45)
        let end = BrowserSearchProviderBloom.frame(at: duration)
        XCTAssertEqual(start, .rest)
        // Ease-out: a third of the rise takes well over a third of the strength.
        XCTAssertGreaterThan(early.strength, 0.4)
        XCTAssertGreaterThanOrEqual(peak.strength, 0.95)
        XCTAssertLessThan(fading.strength, peak.strength)
        XCTAssertEqual(end.strength, 0, accuracy: 0.001)
        XCTAssertGreaterThan(fading.spread, peak.spread)
    }

    func testReduceTransparencyAndIncreaseContrastDrawNoBlur() {
        XCTAssertTrue(BrowserSearchProviderGlow.showsBlur(reduceTransparency: false, contrast: .standard))
        XCTAssertFalse(BrowserSearchProviderGlow.showsBlur(reduceTransparency: true, contrast: .standard))
        XCTAssertFalse(BrowserSearchProviderGlow.showsBlur(reduceTransparency: false, contrast: .increased))
    }

    func testAProviderOwnsItsSiteAndItsSubdomainsOnly() throws {
        let browser = BrowserStore(seed: .preview)
        BrowserSearchCatalog.restore(into: browser.core, locale: Locale(identifier: "en_US"))
        let catalog = BrowserSearchCatalog(core: browser.core)
        let youTube = try XCTUnwrap(catalog.providers.first { $0.builtIn == .youTube })

        XCTAssertEqual(youTube.site, "youtube.com")
        for address in ["youtube.com", "www.youtube.com/feed", "https://m.youtube.com/watch?v=1", "YouTube.com"] {
            XCTAssertTrue(youTube.isSite(of: address), address)
        }
        for address in ["notyoutube.com", "youtube.com.example.org", "https://example.com/youtube.com", ""] {
            XCTAssertFalse(youTube.isSite(of: address), address)
        }
    }

    func testARowNamesThePageItOpensByItsDomainAfterItsTitle() throws {
        let history = row(
            .history, title: "YouTube", subtitle: "https://www.youtube.com/feed",
            address: "https://www.youtube.com/feed")
        XCTAssertEqual(BrowserCommandPaletteRowLabel.detail(for: history), "youtube.com")

        let tab = row(.tab, title: "Swift Evolution", subtitle: "www.swift.org", tabID: UUID())
        XCTAssertEqual(BrowserCommandPaletteRowLabel.detail(for: tab), "swift.org")

        let open = row(
            .openAddress, title: "Open youtube.com", subtitle: "https://youtube.com", address: "https://youtube.com")
        XCTAssertEqual(BrowserCommandPaletteRowLabel.detail(for: open), "", "The title already names the site.")

        let command = row(.command, title: "Show History", subtitle: "View")
        XCTAssertEqual(BrowserCommandPaletteRowLabel.detail(for: command), "View")

        let browser = BrowserStore(seed: .preview)
        BrowserSearchCatalog.restore(into: browser.core, locale: Locale(identifier: "en_US"))
        let google = try XCTUnwrap(BrowserSearchCatalog(core: browser.core).providers.first { $0.builtIn == .google })
        let search = row(
            .search, title: "Search Google", subtitle: "you", address: "https://www.google.com/search?q=you",
            provider: google)
        XCTAssertEqual(BrowserCommandPaletteRowLabel.detail(for: search), "you", "A search names what it searches.")
    }

    func testATabTitleSetsInBoldThePartsTheCoreMatched() async throws {
        let titles = [
            "Swift Evolution": "https://www.swift.org/swift-evolution/",
            "Café Society": "https://cafe.example.test/",
            "banana bandana": "https://fruit.example.test/",
            "Emoji \u{1F600} party": "https://celebration.example.test/",
        ]
        let source = TabState.Seed.startPage()
        let tabs = titles.sorted { $0.key < $1.key }.map { title, address in
            TabState.Seed(title: title, url: URL(string: address), placement: .current)
        }
        let space = SpaceState.Seed(
            name: "Emphasis", symbol: "bold", accent: .indigo, folders: [], tabs: [source] + tabs)
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: source.id])
        let model = BrowserCommandPaletteModel(
            browser: browser, space: browser.spaceModel(space.id), selectedTabID: source.id, initialQuery: "",
            commands: nil,
            lookups: BrowserCommandPaletteLookups(
                fetchSuggestions: { _ in [] }, lookUpDefinition: { _ in nil }, fetchWebSummary: { _ in nil }),
            isSourceAvailable: { _ in true }, selectTab: { _, _ in false }, openURL: { _, _, _ in false }, dismiss: {})
        // UTF-16 offset and length of each bold run, by the tab title it marks.
        let expected: [(query: String, title: String, runs: [[Int]])] = [
            ("evo", "Swift Evolution", [[6, 3]]),
            ("swift evo", "Swift Evolution", [[0, 5], [6, 3]]),
            ("café", "Café Society", [[0, 4]]),
            // Matching ignores accents, so "cafe" marks "Café".
            ("cafe", "Café Society", [[0, 4]]),
            ("ana", "banana bandana", [[1, 3], [11, 3]]),
            ("party", "Emoji \u{1F600} party", [[9, 5]]),
        ]
        for (query, title, runs) in expected {
            model.query = query
            await model.waitForPendingResults()
            let row = try XCTUnwrap(model.items.map(\.row).first { $0.kind == .tab && $0.title == title }, query)
            XCTAssertEqual(boldRuns(of: row), runs, "\(query) in \(title)")
        }
        let outside = row(
            .tab, title: "Ode", subtitle: "",
            emphasis: PaletteEmphasis(runs: [TextRun(start: 0, length: 1), TextRun(start: 2, length: 5)]))
        XCTAssertEqual(boldRuns(of: outside), [[0, 1]], "A run past the end of the title is left out.")
    }

    private func row(
        _ kind: PaletteRowKind, title: String, subtitle: String, address: String? = nil, tabID: UUID? = nil,
        provider: SearchProvider? = nil, emphasis: PaletteEmphasis? = nil
    ) -> PaletteRow {
        PaletteRow(
            kind: kind, title: title, subtitle: subtitle, symbol: kind.symbol, subjectID: nil, tabID: tabID,
            address: address, command: nil, provider: provider, settingsPage: nil, scope: nil, reason: nil, answer: nil,
            topResult: nil, card: nil, emphasis: emphasis)
    }

    /// The UTF-16 offset and length of each run of `row`'s title the row
    /// label sets in bold.
    private func boldRuns(of row: PaletteRow) -> [[Int]] {
        guard let text = BrowserCommandPaletteEmphasis.title(of: row) else { return [] }
        return text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { run in
            [
                String(text[text.startIndex..<run.range.lowerBound].characters).utf16.count,
                String(text[run.range].characters).utf16.count,
            ]
        }
    }
}
