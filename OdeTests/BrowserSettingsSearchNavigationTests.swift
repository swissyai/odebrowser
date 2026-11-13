import Foundation
import XCTest

@testable import Ode

@MainActor
final class BrowserSettingsSearchNavigationTests: XCTestCase {
    // MARK: - Actions - Search navigation

    func testSearchRoutesToAnIndividualSettingBeforeAPageOnlyMatch() {
        let locale = Locale(identifier: "en_US")
        var navigation = BrowserSettingsNavigationState(searchText: "camera")
        navigation.landOnSearchResults(in: [.general, .privacy], locale: locale)
        XCTAssertEqual(navigation.destination, .privacy)

        navigation.searchText = "update"
        navigation.landOnSearchResults(in: [.general, .about], locale: locale)
        XCTAssertEqual(navigation.destination, .about)
    }

    func testIntelligenceSearchAndStableTargetRouteToSearch() {
        let locale = Locale(identifier: "en_US")
        let target = BrowserSettingsSearchTarget.named("intelligence")
        XCTAssertEqual(target?.destination, .search)

        var navigation = BrowserSettingsNavigationState(
            selection: .destination(.lookAndFeel), searchText: "Apple Intelligence")
        let destinations = BrowserSettingsDestination.all.filter {
            $0.matchesSearchQuery(navigation.query, locale: locale)
        }
        navigation.landOnSearchResults(in: destinations, locale: locale)
        XCTAssertEqual(navigation.destination, .search)
        XCTAssertEqual(
            BrowserSettingsSearchTarget.matching(navigation.query, on: .search, locale: locale), [.intelligence])
        XCTAssertTrue(
            BrowserSettingsSearchTarget.matching(navigation.query, on: .lookAndFeel, locale: locale).isEmpty)
    }

    func testClearingOrUnmatchedSearchDoesNotReplaceTheCurrentPage() {
        let locale = Locale(identifier: "en_US")
        var navigation = BrowserSettingsNavigationState(selection: .destination(.about), searchText: " ")
        navigation.landOnSearchResults(in: [.general, .about], locale: locale)
        XCTAssertEqual(navigation.destination, .about)
        XCTAssertTrue(BrowserSettingsSearchTarget.matching(navigation.query, on: .about, locale: locale).isEmpty)

        navigation.searchText = "unmatched-query"
        navigation.landOnSearchResults(in: [], locale: locale)
        XCTAssertEqual(navigation.destination, .about)
    }

    func testSearchListsThePagesAndSettingsHoldingEveryWordTyped() {
        let locale = Locale(identifier: "en_US")
        let expected: [(query: String, pages: [String], rows: [String])] = [
            ("camera", ["general", "privacy"], ["permission-camera"]),
            ("update", ["about"], ["automatic-updates", "automatic-install", "idle-restart", "update-channel"]),
            ("PiP", ["general"], ["picture-in-picture"]),
            ("Kagi", ["search"], ["default-search"]),
            ("iCloud", ["sync", "passwords"], []),
            ("Default browser", ["general", "engines"], ["default-browser"]),
            ("browser default", ["general", "engines"], ["default-browser"]),
            ("right sidebar", ["lookAndFeel"], ["sidebar-on-right"]),
            ("zz", [], []),
        ]
        for (query, pages, rows) in expected {
            XCTAssertEqual(
                BrowserSettingsDestination.all.filter { $0.matchesSearchQuery(query, locale: locale) }.map(\.name),
                pages,
                query)
            XCTAssertEqual(
                BrowserSettingsDestination.all.flatMap {
                    BrowserSettingsSearchTarget.matching(query, on: $0, locale: locale).map(\.name)
                }, rows, query)
        }
        let state = BrowserStore(seed: SessionState.Seed(spaces: [SpaceState.Seed(name: "One", tabs: [])])).core.state
        XCTAssertEqual(BrowserSpaceSettingsTab.matching("camera", locale: locale, in: state)?.name, "privacy")
        XCTAssertEqual(
            BrowserSpaceSettingsTab.matching("suggestions search", locale: locale, in: state)?.name, "browsing")
    }

    func testPageSearchStillRoutesWhenNoIndividualRowIsIndexed() {
        var navigation = BrowserSettingsNavigationState(searchText: "shortcuts")
        navigation.landOnSearchResults(in: [.shortcuts], locale: Locale(identifier: "en_US"))
        XCTAssertEqual(navigation.destination, .shortcuts)
    }
}
