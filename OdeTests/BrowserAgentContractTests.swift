import Darwin
import XCTest

@testable import Ode

@MainActor
final class BrowserAgentContractTests: XCTestCase {
    // MARK: - Actions - Results

    func testStructuredResultsPreserveDataAndNotesWithoutPromisingEffects() throws {
        let result = AgentToolResult.data(["closed": false], note: "The tab is still open.")
            .noting("A navigation was held for approval.")
        let decoded = try JSONDecoder().decode(AgentToolResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.structuredContent.outcome, .completed)
        XCTAssertEqual(decoded.structuredContent.effect, .unknown)
        XCTAssertEqual(try decoded.structuredContent.data?.decoded(as: [String: Bool].self), ["closed": false])
        XCTAssertEqual(
            decoded.structuredContent.notes, ["The tab is still open.", "A navigation was held for approval."])
        XCTAssertTrue(decoded.content.compactMap(\.text).joined().contains("A navigation was held for approval."))

        let refusal = BrowserAgentFailure.navigationBoundaryUnavailable.result.noting("No page was read.")
        XCTAssertTrue(refusal.isError)
        XCTAssertEqual(refusal.structuredContent.outcome, .unsupported)
        XCTAssertEqual(refusal.structuredContent.effect, .notAttempted)
        XCTAssertEqual(refusal.structuredContent.refusal, .navigationBoundaryUnavailable)
        XCTAssertNil(refusal.structuredContent.data)
        XCTAssertEqual(BrowserAgentFailure.cancelled.result.structuredContent.effect, .unknown)
        XCTAssertEqual(BrowserAgentFailure.timedOut.result.structuredContent.effect, .unknown)
    }

    // MARK: - Actions - Catalog

    /// Agents learn the tools from `AgentToolDefinition.all`; the service
    /// answers them from `BrowserAgentTool.all`. A definition without work
    /// would be advertised and then refused as unknown.
    func testEveryAdvertisedToolHasWorkInTheOrderAgentsListThem() {
        XCTAssertEqual(BrowserAgentTool.all.map(\.definition.name), AgentToolDefinition.all.map(\.name))
    }

    // MARK: - Actions - Cancellation

    func testQueuedCancellationDoesNotRunWorkOrCancelTheEarlierCall() async throws {
        let application = try BrowserMacApplication()
        let host = WebKitShellHost()
        let windows = BrowserMacWindows(application: application, engineHost: host)
        let agents = BrowserMacAgents(application: application, windows: windows)
        defer { withExtendedLifetime(host) {} }
        let tabID = UUID()
        var releaseFirst: CheckedContinuation<Void, Never>?
        let firstStarted = expectation(description: "Earlier tab work started")
        let first = Task {
            try await agents.serially(on: tabID) { () async throws(BrowserAgentFailure) -> AgentToolResult in
                await withCheckedContinuation { continuation in
                    releaseFirst = continuation
                    firstStarted.fulfill()
                }
                return .message("Earlier work completed")
            }
        }
        await fulfillment(of: [firstStarted], timeout: 2)
        let fixture = try AgentLinkFixture()
        defer {
            fixture.close()
            releaseFirst?.resume()
        }
        let link = fixture.link
        var performed = false
        var failure: BrowserAgentFailure?
        let second = Task {
            do throws(BrowserAgentFailure) {
                _ = try await agents.serially(on: tabID) { () async throws(BrowserAgentFailure) -> AgentToolResult in
                    performed = true
                    return .message("Must not run")
                }
            } catch {
                failure = error
            }
        }
        link.calls[17] = second
        await Task.yield()
        AgentLinkRequest.cancel(id: 18).handle(on: agents, from: link)
        XCTAssertFalse(second.isCancelled, "Cancellation must target only the named call")
        let data = try JSONEncoder().encode(AgentLinkRequest.cancel(id: 17))
        let decoded = try JSONDecoder().decode(AgentLinkRequest.self, from: data)
        decoded.handle(on: agents, from: link)
        XCTAssertTrue(second.isCancelled)
        XCTAssertFalse(first.isCancelled, "A queued call must not cancel earlier work")
        releaseFirst?.resume()
        releaseFirst = nil
        let firstResult = try await first.value
        XCTAssertFalse(firstResult.isError)
        await second.value
        XCTAssertEqual(failure?.outcome, .cancelled)
        XCTAssertEqual(failure?.effect, .unknown, "Cancellation is not a rollback receipt")
        XCTAssertFalse(performed)
    }

    // MARK: - Actions - Authorization

    func testScriptRechecksPermissionRevokedWhileItsPageSettles() async throws {
        let application = try BrowserMacApplication()
        let host = WebKitShellHost()
        let windows = BrowserMacWindows(application: application, engineHost: host)
        let agents = BrowserMacAgents(application: application, windows: windows)
        let core = application.browser.core
        let space = try XCTUnwrap(application.browser.shownSpace)
        let tabID = try XCTUnwrap(
            application.browser.openNewTab(url: try XCTUnwrap(URL(string: "about:blank")), in: space.id))
        let identity = AgentIdentity(teamID: nil, signingID: nil, path: "/fixture/agent", client: nil)
        let sessionID = UUID()
        try core.send(SetAgents(isOn: true))
        try core.send(SetAgentScripts(runsScripts: true))
        try core.send(AllowAgentSpace(spaceID: space.id, allowed: true))
        try core.send(ApproveAgent(agent: ApprovedAgent(identity: identity, name: "Fixture")))
        try core.send(BeginAgentSession(sessionID: sessionID, identity: identity, name: "Fixture"))
        let fixture = try AgentLinkFixture(sessionID: sessionID)
        let link = fixture.link
        defer {
            fixture.close()
            application.pages.reconcile(validTabIDs: [])
            withExtendedLifetime(host) {}
        }
        let script = Task { @MainActor () async -> Result<AgentToolResult, BrowserAgentFailure> in
            do throws(BrowserAgentFailure) {
                return .success(
                    try await agents.evaluateScript(
                        BrowserAgentCall(
                            agents: agents, link: link, sessionID: sessionID,
                            arguments: .object([
                                "tab": .string(tabID.uuidString),
                                "function": .string("globalThis.agentPermissionProbe = true; return 1;"),
                            ]))))
            } catch {
                return .failure(error)
            }
        }
        defer { script.cancel() }
        // Synchronize on real ownership, not a callback before the script's
        // initial permission check. The blank page is still settling.
        let deadline = ContinuousClock.now + .seconds(2)
        while !link.drivenTabs.contains(tabID), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(link.drivenTabs.contains(tabID), "The initial permission check must have passed")
        let page = try XCTUnwrap(application.pages.residentPage(ofTab: tabID))
        let webView = try XCTUnwrap(page.webKitView)
        try core.send(SetAgentScripts(runsScripts: false))
        // Complete the pending document using local test content only.
        webView.loadHTMLString("<title>Permission fixture</title><p>Ready</p>", baseURL: nil)
        switch await script.value {
        case .success:
            XCTFail("A script ran after permission was revoked during page settlement")
        case .failure(let failure):
            XCTAssertEqual(failure.refusal, .scriptsDisabled)
        }
        let executed = try await webView.evaluateJavaScript("globalThis.agentPermissionProbe === true")
        XCTAssertEqual(executed as? Bool, false)
    }
}
