import Foundation
import XCTest

@testable import Ode

/// A test or harness run never reaches a live service with Ode's name: the
/// Command Bar's suggestion and Wikipedia requests go to a fixture server on
/// this Mac when the run names one, and nowhere when it names none, while an
/// ordinary launch fetches where the core says.
final class BrowserNetworkFixtureTests: XCTestCase {
    // MARK: - Variables

    private let summary = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/Marie_Curie?redirect=true")!

    // MARK: - Actions - Privacy

    func testAFixtureRedirectCannotForwardClientHeadersWhileOrdinaryRequestsStillRedirect() async throws {
        let source = try BrowserPrivacyHTTPServer()
        let destination = try BrowserPrivacyHTTPServer()
        try await source.start()
        try await destination.start()
        defer {
            source.stop()
            destination.stop()
        }
        let target = destination.url(host: "127.0.0.1", path: "/destination")
        source.overrideResponse = { _ in ("302 Found", "Location: \(target.absoluteString)\r\n", Data()) }
        destination.overrideResponse = { _ in ("200 OK", "Content-Type: application/json\r\n", Data("[]".utf8)) }
        let session = URLSession(configuration: BrowserWebAnswerClient.sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: source.url(host: "127.0.0.1", path: "/fixture"))

        let (_, blocked) = try await session.data(for: request, delegate: BrowserNetworkFixture.redirectGuard)
        XCTAssertEqual((blocked as? HTTPURLResponse)?.statusCode, 302)
        XCTAssertEqual(source.requests.count, 1)
        XCTAssertTrue(destination.requests.isEmpty)

        let (_, ordinary) = try await session.data(for: request)
        XCTAssertEqual((ordinary as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(destination.requests.count, 1)
        XCTAssertEqual(destination.requests.first?.headers["user-agent"], BrowserWebAnswerClient.userAgent)
    }

    func testARunThatNamesAFixtureServerFetchesFromItUnderTheOriginalHost() {
        let routed = BrowserNetworkFixture.routed(
            summary, environment: [BrowserNetworkFixture.environmentKey: "http://127.0.0.1:8765"], isTestHost: true)
        XCTAssertEqual(
            routed?.absoluteString,
            "http://127.0.0.1:8765/en.wikipedia.org/api/rest_v1/page/summary/Marie_Curie?redirect=true")
    }

    func testATestOrHarnessRunWithoutOneFetchesNothing() {
        XCTAssertNil(BrowserNetworkFixture.routed(summary, environment: [:], isTestHost: true))
        XCTAssertNil(BrowserNetworkFixture.routed(summary, environment: ["ODE_TEST_HARNESS": "1"], isTestHost: false))
        let remote = [BrowserNetworkFixture.environmentKey: "https://fixtures.example/"]
        XCTAssertNil(BrowserNetworkFixture.routed(summary, environment: remote, isTestHost: true))
        XCTAssertEqual(BrowserNetworkFixture.routed(summary, environment: [:], isTestHost: false), summary)
    }

    func testTypedPageNavigationUsesTheSameLocalBoundary() {
        let remote = URL(string: "https://duckduckgo.com/?q=%5Cfixture")!
        XCTAssertNil(BrowserNetworkFixture.navigation(remote))
        for address in [
            "http://127.0.0.1:8765/landing", "http://localhost:8765/landing", "about:blank", "data:text/html,local",
        ] {
            let url = URL(string: address)!
            XCTAssertEqual(BrowserNetworkFixture.navigation(url), url)
        }
    }

    func testTheClientsInThisTestHostReachNoLiveService() async {
        let suggestions = try? await BrowserSearchSuggestionClient.shared.suggestions(
            from: URL(string: "https://duckduckgo.com/ac/?q=ode&type=list")!)
        XCTAssertEqual(suggestions, [])
        let lookup = PaletteWebLookup(
            topic: "Marie Curie",
            searchAddress: "https://en.wikipedia.org/w/rest.php/v1/search/title?q=Marie%20Curie&limit=1",
            summaryTemplate: "https://en.wikipedia.org/api/rest_v1/page/summary/%s",
            imageInfoTemplate: "https://commons.wikimedia.org/%s")
        let fetched = await BrowserWebAnswerClient.shared.summary(for: lookup)
        XCTAssertNil(fetched)
    }
}
