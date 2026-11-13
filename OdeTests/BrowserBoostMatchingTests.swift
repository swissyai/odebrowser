import XCTest

@testable import Ode

/// Which Boost a page wears: a Boost applies to the page's site
/// (`BrowserSite`) alone, and only Boosts that are on and change something
/// put CSS on pages. A document's messages are read only in the shape the
/// Boost script posts.
@MainActor
final class BrowserBoostMatchingTests: XCTestCase {
    private func boost(_ site: String, enabled: Bool = true, hidden: [String] = ["#ads"]) -> SiteBoost {
        var boost = SiteBoost(blankFor: site)
        boost.isEnabled = enabled
        boost.hiddenSelectors = hidden
        return boost
    }

    func testABoostAppliesToItsSiteAlone() {
        let boosts = SpaceBoosts(sites: [boost("example.com"), boost("docs.example.org", enabled: false)])

        XCTAssertEqual(boosts.boost(for: URL(string: "https://www.example.com/a"))?.site, "example.com")
        XCTAssertEqual(boosts.boost(for: URL(string: "http://example.com/b"))?.site, "example.com")
        XCTAssertNil(boosts.boost(for: URL(string: "https://shop.example.com/")))
        XCTAssertNil(boosts.boost(for: URL(string: "https://notexample.com/")))
        // A Boost that is off still belongs to its site, so it can be turned on.
        XCTAssertEqual(boosts.boost(for: URL(string: "https://docs.example.org/"))?.isEnabled, false)
    }

    func testOnlyBoostsThatAreOnAndChangeSomethingPutCSSOnPages() {
        let boosts = SpaceBoosts(sites: [
            boost("example.com"), boost("off.example", enabled: false), boost("blank.example", hidden: []),
        ])

        XCTAssertEqual(Array(boosts.stylesheets.keys), ["example.com"])
        XCTAssertTrue(boosts.stylesheets["example.com"]?.contains("#ads { display: none !important; }") == true)
        XCTAssertEqual(SiteBoost(blankFor: "blank.example").stylesheet, "")
    }

    func testADocumentIsHeardOnlyInTheShapeTheBoostScriptPosts() {
        let hid = BrowserBoostPageMessage(body: [
            "version": 1, "kind": "zapped", "site": "example.com", "selector": "#ads",
        ])
        XCTAssertEqual(hid?.kind, .hid)
        XCTAssertEqual(hid?.selector, "#ads")
        XCTAssertEqual(
            BrowserBoostPageMessage(body: ["version": 1, "kind": "ready", "site": "example.com"])?.kind, .ready)

        XCTAssertNil(BrowserBoostPageMessage(body: ["version": 2, "kind": "ready", "site": "example.com"]))
        XCTAssertNil(BrowserBoostPageMessage(body: ["version": 1, "kind": "remove", "site": "example.com"]))
        XCTAssertNil(BrowserBoostPageMessage(body: ["version": 1, "kind": "zapped", "site": "example.com"]))
        XCTAssertNil(
            BrowserBoostPageMessage(body: [
                "version": 1, "kind": "zapped", "site": "example.com",
                "selector": String(repeating: "a", count: SiteBoost.maximumSelectorLength + 1),
            ]))
        XCTAssertNil(BrowserBoostPageMessage(body: "ready"))
    }
}
