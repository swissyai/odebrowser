import Foundation
import XCTest

@testable import Ode

final class OdeFuzzyMatcherTests: XCTestCase {
    private func names(_ query: String, in entries: [OdeFuzzyIndex.Entry]) -> [String] {
        OdeFuzzySearcher(index: OdeFuzzyIndex(entries)).search(query).map { entries[Int($0.index)].primary }
    }

    func testWordStartsAndConsecutiveLettersRankFirst() {
        let entries: [OdeFuzzyIndex.Entry] = [
            .init(primary: "abriefcase"), .init(primary: "brief.case"), .init(primary: "briefcase"),
            .init(primary: "bxrxixexf"),
        ]
        XCTAssertEqual(names("brief", in: entries).first, "brief.case")
        XCTAssertEqual(names("briefcase", in: entries).first, "briefcase")
        XCTAssertEqual(names("brief", in: entries).last, "bxrxixexf", "the most scattered match ranks last")
    }

    func testSpreadMatchesOnlyShowWhenLittleElseMatches() {
        var entries = (0..<8).map { OdeFuzzyIndex.Entry(primary: "travel \($0)") }
        entries.append(.init(primary: "grinning face with sweat", secondary: "travel"))
        entries.append(.init(primary: "tram over level road"))
        let found = names("travel", in: entries)
        XCTAssertTrue(found.contains("grinning face with sweat"), "a whole keyword is a strong match")
        XCTAssertFalse(
            found.contains("tram over level road"), "a match spread over words is dropped when enough else matches")
        XCTAssertEqual(names("travel", in: [.init(primary: "tram over level road")]), ["tram over level road"])
    }

    func testAWholeKeywordOutranksAPrefixOfAName() {
        let entries: [OdeFuzzyIndex.Entry] = [
            .init(primary: "Construction worker", secondary: "builder"),
            .init(primary: "briefcase", secondary: "work job office"),
        ]
        XCTAssertEqual(names("work", in: entries), ["briefcase", "Construction worker"])
    }

    func testMatchesSpreadAcrossWordsRankAfterTypos() {
        let entries: [OdeFuzzyIndex.Entry] = [
            .init(primary: "backpack.sensor.tag.radiowaves.left"), .init(primary: "calendar"),
            .init(primary: "car.top.lane.dashed.arrow"),
        ]
        let hits = OdeFuzzySearcher(index: OdeFuzzyIndex(entries)).search("calnedar")
        XCTAssertEqual(entries[Int(hits[0].index)].primary, "calendar")
        XCTAssertEqual(hits[0].edits, 1)
        let spread = OdeFuzzySearcher(index: OdeFuzzyIndex(entries)).search("trvel")
        XCTAssertTrue(spread.allSatisfy(\.isWeak))
    }

    func testTyposNeedFourLettersAndKeepTheFirstLetter() {
        let entries: [OdeFuzzyIndex.Entry] = [
            .init(primary: "travel"), .init(primary: "gravel"), .init(primary: "car"),
        ]
        XCTAssertEqual(names("trevel", in: entries), ["travel"])
        XCTAssertEqual(names("cra", in: entries), [], "three letters allow no typo")
    }

    func testNarrowingFindsWhatAFreshSearchFinds() {
        let entries = ["airplane", "airplane.departure", "car", "car.fill", "house", "heart", "briefcase", "globe"]
            .map { OdeFuzzyIndex.Entry(primary: $0) }
        let index = OdeFuzzyIndex(entries)
        let typing = OdeFuzzySearcher(index: index)
        for query in ["a", "ai", "air", "airp", "airpl"] {
            let narrowed = typing.search(query)
            let fresh = OdeFuzzySearcher(index: index).search(query)
            XCTAssertEqual(narrowed, fresh, query)
        }
    }

    func testFoldingIgnoresCaseAndAccents() {
        let entries: [OdeFuzzyIndex.Entry] = [.init(primary: "Café"), .init(primary: "cafeteria tray")]
        XCTAssertEqual(names("CAFE", in: entries).first, "Café")
    }

    /// The scores the alignment gives a fixed set of queries and texts:
    /// single letters, runs, word and case boundaries, gaps, a decayed
    /// alignment, typos and keywords.
    func testAlignmentScoresStayAsTheyAre() {
        let primaries = [
            "airplane", "airplane.departure", "arrow.up.right", "briefcase", "brief.case", "abriefcase", "bxrxixexf",
            "CamelCaseName", "heart.fill", "house", "travel", "tram over level road",
            "a" + String(repeating: "x", count: 40) + "e", "x", "Café au lait", "calendar.badge.plus",
            "car.top.lane.dashed.arrow",
        ]
        let entries =
            primaries.map { OdeFuzzyIndex.Entry(primary: $0) } + [
                OdeFuzzyIndex.Entry(primary: "grinning face", secondary: "happy travel smile")
            ]
        let index = OdeFuzzyIndex(entries)
        let expected: [(String, [(String, Int32, Int8, Bool)])] = [
            (
                "a",
                [
                    ("airplane", 36, 0, false), ("airplane.departure", 36, 0, false), ("arrow.up.right", 36, 0, false),
                    ("abriefcase", 36, 0, false), ("axxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe", 36, 0, false),
                    ("Café au lait", 36, 0, false), ("car.top.lane.dashed.arrow", 34, 0, false),
                    ("briefcase", 16, 0, false), ("brief.case", 16, 0, false), ("CamelCaseName", 16, 0, false),
                    ("heart.fill", 16, 0, false), ("travel", 16, 0, false), ("tram over level road", 16, 0, false),
                    ("calendar.badge.plus", 16, 0, false), ("grinning face", 16, 0, false),
                ]
            ),
            (
                "x",
                [
                    ("x", 36, 0, false), ("bxrxixexf", 16, 0, false),
                    ("axxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe", 16, 0, false),
                ]
            ),
            (
                "e",
                [
                    ("airplane", 16, 0, false), ("airplane.departure", 16, 0, false), ("briefcase", 16, 0, false),
                    ("brief.case", 16, 0, false), ("abriefcase", 16, 0, false), ("bxrxixexf", 16, 0, false),
                    ("CamelCaseName", 16, 0, false), ("heart.fill", 16, 0, false), ("house", 16, 0, false),
                    ("travel", 16, 0, false), ("tram over level road", 16, 0, false),
                    ("axxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe", 16, 0, false), ("Café au lait", 16, 0, false),
                    ("calendar.badge.plus", 16, 0, false), ("car.top.lane.dashed.arrow", 16, 0, false),
                    ("grinning face", 16, 0, false),
                ]
            ),
            (
                "br",
                [
                    ("briefcase", 62, 0, false), ("brief.case", 62, 0, false), ("bxrxixexf", 49, 0, false),
                    ("abriefcase", 36, 0, false),
                ]
            ),
            (
                "brief",
                [
                    ("brief.case", 220, 0, false), ("briefcase", 140, 0, false), ("abriefcase", 96, 0, false),
                    ("bxrxixexf", 88, 0, false),
                ]
            ),
            (
                "case",
                [
                    ("brief.case", 157, 0, false), ("CamelCaseName", 139, 0, false), ("briefcase", 76, 0, false),
                    ("abriefcase", 76, 0, false), ("Café au lait", 12, 1, false), ("calendar.badge.plus", 12, 1, false),
                    ("car.top.lane.dashed.arrow", 16, 0, true), ("grinning face", 16, 0, true),
                ]
            ),
            ("bc", [("briefcase", 46, 0, false), ("abriefcase", 26, 0, false), ("brief.case", 8, 0, true)]),
            ("fbc", []),
            ("dep", [("airplane.departure", 84, 0, false), ("calendar.badge.plus", 12, 0, true)]),
            (
                "ap",
                [
                    ("airplane", 48, 0, false), ("airplane.departure", 48, 0, false), ("grinning face", 28, 0, false),
                    ("arrow.up.right", 8, 0, true), ("calendar.badge.plus", 8, 0, true),
                    ("car.top.lane.dashed.arrow", 8, 0, true),
                ]
            ),
            (
                "ae",
                [
                    ("abriefcase", 47, 0, false), ("airplane", 29, 0, false), ("airplane.departure", 29, 0, false),
                    ("briefcase", 29, 0, false), ("brief.case", 29, 0, false), ("CamelCaseName", 29, 0, false),
                    ("travel", 29, 0, false), ("Café au lait", 29, 0, false), ("calendar.badge.plus", 29, 0, false),
                    ("car.top.lane.dashed.arrow", 29, 0, false), ("grinning face", 29, 0, false),
                    ("axxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe", 1, 0, false),
                ]
            ),
            ("arw", [("arrow.up.right", 74, 0, false), ("car.top.lane.dashed.arrow", 71, 0, false)]),
            ("heart", [("heart.fill", 220, 0, false)]),
            ("hrt", [("heart.fill", 68, 0, false)]),
            ("camelcase", [("CamelCaseName", 36, 0, true)]),
            (
                "cn",
                [
                    ("calendar.badge.plus", 47, 0, false), ("CamelCaseName", 8, 0, true),
                    ("car.top.lane.dashed.arrow", 8, 0, true),
                ]
            ),
            (
                "travel",
                [("travel", 246, 0, false), ("grinning face", 180, 0, false), ("tram over level road", 24, 0, true)]
            ),
            (
                "tvl",
                [("travel", 61, 0, false), ("grinning face", 48, 0, false), ("tram over level road", 12, 0, true)]
            ),
            ("zz", []),
            ("air plane", [("airplane", 184, 0, false), ("airplane.departure", 184, 0, false)]),
            (
                "cafe",
                [
                    ("Café au lait", 194, 0, false), ("brief.case", 12, 1, false), ("CamelCaseName", 12, 1, false),
                    ("calendar.badge.plus", 12, 1, false),
                ]
            ),
            ("calbad", [("calendar.badge.plus", 24, 0, true)]),
            ("smile", [("grinning face", 160, 0, false)]),
            ("lane arrow", [("car.top.lane.dashed.arrow", 339, 0, false)]),
        ]
        for (query, hits) in expected {
            let found = OdeFuzzySearcher(index: index).search(query).map {
                "\(entries[Int($0.index)].primary) \($0.score) \($0.edits) \($0.isWeak)"
            }
            XCTAssertEqual(found, hits.map { "\($0.0) \($0.1) \($0.2) \($0.3)" }, query)
        }
    }

    /// One keystroke at a time over every symbol and emoji the picker offers,
    /// as a person types. Timing only means something in an optimized build,
    /// one compiled without assertions.
    func testKeystrokesOverTheWholeCorpusStayUnderOneMillisecond() throws {
        guard OdeFuzzyIndex.isOptimizedBuild else {
            throw XCTSkip("Search timing is asserted in an optimized build.")
        }
        let catalog = BrowserIconCatalog.load(symbolNames: BrowserSystemSymbolCatalog.availableNames())
        XCTAssertGreaterThan(catalog.symbols.count, 5_000)
        let entries =
            catalog.symbols.map { OdeFuzzyIndex.Entry(primary: $0.name, secondary: $0.keywords.joined(separator: " ")) }
            + catalog.emoji.map {
                OdeFuzzyIndex.Entry(primary: $0.choice.name, secondary: $0.keywords.joined(separator: " "))
            }
        let searcher = OdeFuzzySearcher(index: OdeFuzzyIndex(entries))
        let queries = [
            "briefcase", "travel", "home", "music", "heart", "airplane", "trvel", "food", "money", "office",
            "calendar", "car fill", "book", "star", "globe", "house", "work", "camera", "photo", "game",
        ]
        var timings: [Double] = []
        for _ in 0..<5 {
            for query in queries {
                _ = searcher.search("")
                for end in 1...query.count {
                    let start = DispatchTime.now().uptimeNanoseconds
                    _ = searcher.search(String(query.prefix(end)))
                    timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                }
            }
        }
        timings.sort()
        let p95 = timings[Int(Double(timings.count) * 0.95)]
        XCTAssertLessThan(p95, 1, "p95 \(p95) ms, median \(timings[timings.count / 2]) ms")
    }
}
