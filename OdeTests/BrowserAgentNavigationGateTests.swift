import WebKit
import XCTest

@testable import Ode

/// The site check on every top-level navigation in a tab an agent drives,
/// whatever starts it: a click, a redirect after it or a window it opens
/// reaches a site the person hasn't allowed only once they allow it, while
/// the tab's own site and the person's clicks after explicit release go on.
@MainActor
final class BrowserAgentNavigationGateTests: XCTestCase {
    // MARK: - Variables

    private var pools: [BrowserPagePool] = []
    private var server: BrowserPrivacyHTTPServer?

    // MARK: - Actions - Lifecycle

    override func tearDown() async throws {
        server?.stop()
        pools.removeAll()
        try await super.tearDown()
    }

    // MARK: - Actions - Navigation

    func testUnavailableScreenshotsNeverRequestPageWork() async {
        var requestedPageWork = false
        func requestPageWork() throws(BrowserAgentFailure) -> BrowserAgentCall {
            requestedPageWork = true
            throw .noPage
        }
        do {
            _ = try await BrowserAgentTool.screenshot.perform(try requestPageWork())
            XCTFail("A renderer without trusted redaction must not return screenshot content.")
        } catch {
            XCTAssertEqual(error.message, BrowserAgentFailure.screenshotUnavailable.message)
            XCTAssertEqual(error.outcome, .unsupported)
            XCTAssertEqual(error.refusal, .screenshotRedactionUnavailable)
            XCTAssertEqual(error.effect, .notAttempted)
        }
        XCTAssertFalse(requestedPageWork, "No page lookup, capture callback or image production may begin.")
    }

    func testAnAgentsClickToASiteThePersonHasntAllowedWaitsForThem() async throws {
        let (page, tabID, gate) = try await drivenPage()

        try await follow("#elsewhere", on: page)

        try await waitUntil("the person is asked") { gate.request(for: tabID)?.origin == self.other }
        XCTAssertEqual(page.webView.url?.path, "/start", "Nothing of the other site loads.")
        XCTAssertEqual(gate.takeHeld(tabID), other, "The agent hears what waits.")
        XCTAssertNil(gate.takeHeld(tabID), "It hears it once.")
    }

    func testAScriptNavigationAndFormPostWaitBeforeContactingANewOrigin() async throws {
        let (page, tabID, gate) = try await drivenPage()
        _ = try await page.webView.evaluateJavaScript("location.href = '\(otherURL("/script"))'; true")
        try await waitUntil("the script navigation is held") { gate.request(for: tabID)?.origin == self.other }
        XCTAssertFalse(server?.requests.contains { $0.path == "/script" } ?? true)
        _ = gate.takeHeld(tabID)

        _ = try await page.webView.evaluateJavaScript(
            """
            const form = document.createElement('form'); form.method = 'POST';
            form.action = '\(otherURL("/posted"))'; document.body.append(form); form.submit(); true
            """)
        try await waitUntil("the POST is held") { gate.takeHeld(tabID) == self.other }
        XCTAssertFalse(server?.requests.contains { $0.path == "/posted" } ?? true)
        XCTAssertEqual(page.webView.url?.path, "/start")
    }

    func testARedirectToASiteThePersonHasntAllowedWaitsForThem() async throws {
        let (page, tabID, gate) = try await drivenPage()

        try await follow("#hop", on: page)

        try await waitUntil("the person is asked") { gate.request(for: tabID)?.origin == self.other }
        XCTAssertFalse(server?.requests.contains { $0.path == "/landed" } ?? true, "The other site hears nothing.")
        XCTAssertNotEqual(page.webView.url?.path, "/landed")
    }

    func testAnAppStartedFirstLoadChecksItsRedirectBeforeContactingANewOrigin() async throws {
        let (page, tabID, gate) = try await drivenPage(loading: nil)
        gate.allow("http://127.0.0.1:\(port)")

        page.corePage.load(try XCTUnwrap(server).url(host: "127.0.0.1", path: "/hop"))

        try await waitUntil("the initial-load redirect is held") { gate.request(for: tabID)?.origin == self.other }
        // The gate records its question before WebKit receives the cancellation.
        // Its provisional URL can still name the redirect until that completes.
        try await waitUntil("the cancelled initial load finishes") { !page.webView.isLoading }
        XCTAssertTrue(server?.requests.contains { $0.path == "/hop" } ?? false)
        XCTAssertFalse(server?.requests.contains { $0.path == "/landed" } ?? true)
        XCTAssertNotEqual(page.webView.url?.path, "/landed")
    }

    func testAWindowOpenedForASiteThePersonHasntAllowedWaitsForThem() async throws {
        let (page, tabID, gate) = try await drivenPage()

        _ = try await page.webView.evaluateJavaScript("window.open('\(otherURL("/popup"))'); true")

        try await waitUntil("the person is asked") { gate.request(for: tabID)?.origin == self.other }
        XCTAssertFalse(server?.requests.contains { $0.path == "/popup" } ?? true)
    }

    func testASameOriginWindowsLaterNavigationStillWaitsForApproval() async throws {
        let (page, tabID, gate) = try await drivenPage()
        _ = try await page.webView.evaluateJavaScript("window.agentPopup = window.open('/popup'); true")
        try await waitUntil("the same-origin popup") { self.server?.requests.contains { $0.path == "/popup" } == true }

        _ = try await page.webView.evaluateJavaScript(
            "window.agentPopup.location.href = '\(otherURL("/escaped"))'; true")

        try await waitUntil("the popup navigation is held") { gate.request(for: tabID)?.origin == self.other }
        XCTAssertFalse(server?.requests.contains { $0.path == "/escaped" } ?? true)
    }

    func testAWindowWithoutAnAddressDoesntOpenWhileTheAgentDrives() async throws {
        let (page, tabID, gate) = try await drivenPage()

        let opened = try await page.webView.evaluateJavaScript("window.open() !== null")

        XCTAssertEqual(opened as? Bool, false)
        XCTAssertEqual(gate.takeHeld(tabID), BrowserAgentOriginGate.blankWindow)
    }

    func testTheTabsOwnSiteAndAllowedSitesOpen() async throws {
        let (page, tabID, gate) = try await drivenPage()

        try await follow("#next", on: page)
        try await waitUntil("the page on the tab's own site") { page.webView.url?.path == "/next" }
        gate.allow(other)
        try await follow("#elsewhere", on: page)

        try await waitUntil("the allowed site") { page.webView.url?.path == "/elsewhere" }
        XCTAssertNil(gate.request(for: tabID))
    }

    func testANonWebNavigationIsRefusedWhileTheAgentDrives() async throws {
        let (page, tabID, gate) = try await drivenPage()
        for address in ["about:blank", "data:text/html,fixture", "mailto:fixture@example.test"] {
            XCTAssertFalse(
                BrowserAgentOriginGate.sessions.admits(
                    navigationTo: try XCTUnwrap(URL(string: address)), inTab: tabID, from: page.webView.url), address)
        }
        XCTAssertNotNil(gate.takeHeld(tabID))
    }

    func testAnIdleClaimStillGuardsDelayedNavigationAndPopupsUntilRelease() async throws {
        let (page, tabID, gate) = try await drivenPage()
        // Beyond the former ten-second expiry, with no intervening agent call.
        try await Task.sleep(for: .seconds(11))
        let destination = try XCTUnwrap(URL(string: otherURL("/delayed")))

        XCTAssertFalse(
            BrowserAgentOriginGate.sessions.admits(
                navigationTo: destination, inTab: tabID, from: page.webView.url))
        XCTAssertFalse(
            BrowserAgentOriginGate.sessions.admitsWindow(
                at: destination, inTab: tabID, from: page.webView.url))
        XCTAssertEqual(gate.request(for: tabID)?.origin, other)

        BrowserAgentOriginGate.sessions.release(tabID, by: gate)
        XCTAssertTrue(
            BrowserAgentOriginGate.sessions.admits(
                navigationTo: destination, inTab: tabID, from: page.webView.url))
    }

    func testThePersonsClicksOpenAfterExplicitHandoff() async throws {
        let (page, tabID, gate) = try await drivenPage()
        BrowserAgentOriginGate.sessions.release(tabID, by: gate)

        try await follow("#elsewhere", on: page)

        try await waitUntil("the other site") { page.webView.url?.path == "/elsewhere" }
        XCTAssertNil(gate.request(for: tabID))
    }

    // MARK: - Fixtures

    private var port: UInt16 { server?.port ?? 0 }
    /// The origin the person hasn't allowed: the same server by another name.
    private var other: String { "http://localhost:\(port)" }

    private func otherURL(_ path: String) -> String { other + path }

    /// A WebKit page at the server's `/start`, in a tab the agent's session
    /// drives now, with links to its own site, to another site and to a
    /// redirect to the other site.
    private func drivenPage(loading path: String? = "/start") async throws
        -> (BrowserPage, UUID, BrowserAgentOriginGate)
    {
        let server = try BrowserPrivacyHTTPServer()
        self.server = server
        let port = { server.port }
        server.overrideResponse = { request in
            switch request.path {
            case "/start", "/next":
                let other = "http://localhost:\(port())"
                let body = """
                    <a id="next" href="/next">Next</a> <a id="elsewhere" href="\(other)/elsewhere">Elsewhere</a>
                    <a id="hop" href="/hop">Hop</a>
                    """
                return ("200 OK", "Content-Type: text/html\r\n", Data(body.utf8))
            case "/hop":
                return ("302 Found", "Location: http://localhost:\(port())/landed\r\n", Data())
            default:
                return ("200 OK", "Content-Type: text/html\r\n", Data("<p>\(request.path)</p>".utf8))
            }
        }
        try await server.start()
        let tab = TabState.Seed.startPage()
        let space = SpaceState.Seed(
            profileID: UUID(), name: "Agent Fixture", symbol: "sparkles", accent: .indigo, folders: [], tabs: [tab])
        let pool = BrowserPagePool(
            browser: .hostingPages(SessionState.Seed(spaces: [space])), usesEphemeralWebsiteDataStores: true)
        pools.append(pool)
        pool.present(tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        if let path {
            page.webView.load(URLRequest(url: server.url(host: "127.0.0.1", path: path)))
            try await waitUntil("the start page") {
                let state =
                    try? await page.webView.evaluateJavaScript("document.readyState + location.pathname") as? String
                return state == "complete" + path
            }
        }
        XCTAssertEqual(page.navigationContext?.tabID, tab.id)
        let gate = BrowserAgentOriginGate()
        gate.enter(UUID(), as: nil)
        BrowserAgentOriginGate.sessions.drive(tab.id, by: gate)
        addTeardownBlock { @MainActor in BrowserAgentOriginGate.sessions.release(tab.id, by: gate) }
        return (page, tab.id, gate)
    }

    /// Follows the link `selector` names, as a click in the page would.
    private func follow(_ selector: String, on page: BrowserPage) async throws {
        _ = try await page.webView.evaluateJavaScript("document.querySelector('\(selector)').click(); true")
    }
}
