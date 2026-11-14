import Darwin
import WebKit
import XCTest

@testable import Ode

/// The native executor must honor live core revocation at each new engine
/// submission, and must not treat an absent input receipt as a rejection.
@MainActor
final class BrowserAgentExecutionTests: XCTestCase {
    // MARK: - Actions - Authorization

    func testAuthorizedScriptAndInputReallyReachTheEngine() async throws {
        let fixture = try AgentExecutionFixture()
        defer { fixture.close() }
        try await fixture.load()
        let script = await fixture.perform(
            .evaluateScript,
            arguments: [
                "function": .string("webkit.messageHandlers.agentExecution.postMessage('evaluation'); return 1;")
            ])
        let input = await fixture.perform(.pressKey, arguments: ["key": .string("Enter")])
        XCTAssertEqual(script.structuredContent.outcome, .completed)
        XCTAssertEqual(input.structuredContent.outcome, .completed)
        XCTAssertEqual(fixture.submissions, ["evaluation", "input"], "Calibrate the real engine-work observer")
        XCTAssertTrue(try fixture.isClaimed())
    }

    func testStopAndSpaceRevocationDuringRenderingSettlementPreventFreshScriptAndInput() async throws {
        for stopsTab in [true, false] {
            for runsScript in [true, false] {
                let fixture = try AgentExecutionFixture()
                defer { fixture.close() }
                fixture.probe("iteration", stopsTab: stopsTab, runsScript: runsScript)
                try await fixture.load()
                fixture.probe("task-create")
                let task = Task {
                    fixture.probe("task-start")
                    return await fixture.perform(
                        runsScript ? .evaluateScript : .pressKey,
                        arguments: runsScript
                            ? [
                                "function": .string(
                                    "webkit.messageHandlers.agentExecution.postMessage('evaluation'); return 1;")
                            ]
                            : ["key": .string("Enter")])
                }
                defer { task.cancel() }
                // holdRendering records its engine receipt before the executor's
                // layout-settlement await. Revoke in that actual await.
                fixture.probe("held-await-start")
                do {
                    try await fixture.waitUntil { fixture.link.heldPages[fixture.tabID] != nil }
                    fixture.probe("held-await-complete")
                } catch {
                    fixture.probe("held-await-error", error: error)
                    throw error
                }
                try fixture.revoke(stopsTab: stopsTab)
                if !stopsTab, !runsScript {
                    // Restoring reach does not restore the pruned claim of an
                    // already-running call, and must not cause a new claim.
                    try fixture.core.send(AllowAgentSpace(spaceID: fixture.spaceID, allowed: true))
                }
                let result = await task.value
                XCTAssertEqual(result.structuredContent.outcome, .refused)
                XCTAssertTrue(fixture.submissions.isEmpty, "Revocation must precede every new engine submission")
                XCTAssertTrue(fixture.core.state.agentPreferences.runsScripts)
                XCTAssertTrue(fixture.core.state.agentSessions.contains { $0.sessionID == fixture.sessionID })
                XCTAssertFalse(try fixture.isClaimed(), "Revalidation must not claim or authorize the tab again")
            }
        }
    }

    func testStopDuringProtectedFieldEvaluationPreventsTheFollowingInput() async throws {
        let fixture = try AgentExecutionFixture()
        defer { fixture.close() }
        try await fixture.load()
        // Observe and delay a real field read without substituting its answer.
        // The native handler revokes through the real core while WebKit is
        // still evaluating; the next input must never be submitted.
        _ = try await fixture.webView.callAsyncJavaScript(
            """
            const active = Object.getOwnPropertyDescriptor(Document.prototype, 'activeElement');
            Object.defineProperty(Document.prototype, 'activeElement', {
              configurable: true,
              get() {
                webkit.messageHandlers.agentExecution.postMessage('field');
                const end = performance.now() + 500;
                while (performance.now() < end) {}
                return active.get.call(this);
              }
            });
            """, arguments: [:], in: nil, contentWorld: WebKitPageAgents.agentWorld)
        fixture.stopOnFieldRead = true
        let result = await fixture.perform(.typeText, arguments: ["text": .string("agent text")])
        XCTAssertTrue(fixture.submissions.contains("field"), "The protected-field evaluation must actually run")
        XCTAssertFalse(fixture.submissions.contains("input"), "No new input may follow the revoked evaluation")
        XCTAssertEqual(result.structuredContent.outcome, .refused)
        XCTAssertFalse(try fixture.isClaimed())
        let value = try await fixture.webView.evaluateJavaScript("document.querySelector('input').value")
        XCTAssertEqual(value as? String, "")
    }

    func testReportDoesNotReclaimAfterSpaceRevocationDuringAlreadySubmittedInput() async throws {
        let fixture = try AgentExecutionFixture()
        defer { fixture.close() }
        try await fixture.load()
        fixture.restoreSpaceOnInput = true
        let result = await fixture.perform(.pressKey, arguments: ["key": .string("Enter"), "report": .bool(true)])
        XCTAssertEqual(fixture.submissions, ["input"])
        XCTAssertEqual(
            result.structuredContent.outcome, .completed, "The input was already submitted before revocation")
        XCTAssertFalse(try fixture.isClaimed(), "A follow-up report must not restore the pruned claim")
    }

    // MARK: - Actions - Input Receipts

    func testInputEffectWithDelayedAcknowledgementIsUnconfirmedRatherThanRefused() async throws {
        let fixture = try AgentExecutionFixture()
        defer { fixture.close() }
        try await fixture.load()
        _ = try await fixture.webView.evaluateJavaScript(
            """
            document.querySelector('input').addEventListener('keydown', () => {
              document.body.dataset.inputEffect = 'received';
              webkit.messageHandlers.agentExecution.postMessage('effect');
              const end = performance.now() + 11000;
              while (performance.now() < end) {}
            }, { once: true });
            """)
        let task = Task { await fixture.perform(.pressKey, arguments: ["key": .string("Enter")]) }
        defer { task.cancel() }
        // Observe an actual EnginePage input request waiting on its identity,
        // not a fabricated delivery callback or a directly constructed result.
        try await fixture.waitUntil { !fixture.page.enginePage.agentWaits.inputs.isEmpty }
        let submitted = Set(fixture.page.enginePage.agentWaits.inputs.keys)
        let inputID = try XCTUnwrap(submitted.first)
        XCTAssertEqual(submitted.count, 1)
        let submittedAt = ContinuousClock.now
        let result = await task.value
        let responseAt = ContinuousClock.now
        XCTAssertGreaterThanOrEqual(submittedAt.duration(to: responseAt), .seconds(9))
        XCTAssertTrue(fixture.submissions.contains("effect"), "Real input took effect before its response timed out")
        XCTAssertEqual(fixture.submissions.filter { $0 == "input" }.count, 1)
        XCTAssertTrue(fixture.page.enginePage.agentWaits.inputs.isEmpty)
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.structuredContent.outcome, .unconfirmed)
        XCTAssertEqual(result.structuredContent.effect, .unknown)
        XCTAssertNil(result.structuredContent.refusal)
        // Observe the actual late presentation for the expired request ID.
        // This installs only a receipt waiter, never resubmits engine work or
        // fabricates an acknowledgement. A second empty-map check cannot prove
        // that the engine ever completed the original request.
        let late = await fixture.lateInputAcknowledgement(for: inputID)
        let acknowledgementAt = ContinuousClock.now
        let acknowledgement = try XCTUnwrap(late, "The real WebKit input completion must arrive after expiry")
        XCTAssertEqual(acknowledgement.inputID, inputID)
        XCTAssertEqual(acknowledgement.pageID, fixture.page.enginePage.id)
        XCTAssertTrue(acknowledgement.delivered)
        XCTAssertFalse(acknowledgement.trusted)
        XCTAssertGreaterThan(acknowledgementAt, responseAt)
        let effect = try await fixture.webView.evaluateJavaScript("document.body.dataset.inputEffect")
        XCTAssertEqual(effect as? String, "received")
        XCTAssertEqual(fixture.submissions.filter { $0 == "input" }.count, 1)
        XCTAssertEqual(fixture.submittedInputs, submitted, "DOM effects and the late receipt belong to the same input")
    }

    func testExplicitNegativeInputReceiptRemainsARefusal() async throws {
        let fixture = try AgentExecutionFixture()
        defer { fixture.close() }
        try await fixture.load()
        _ = try await fixture.webView.evaluateJavaScript("document.querySelector('input').blur()")
        let result = await fixture.perform(.typeText, arguments: ["text": .string("agent text")])
        XCTAssertEqual(result.structuredContent.outcome, .refused)
        let value = try await fixture.webView.evaluateJavaScript("document.querySelector('input').value")
        XCTAssertEqual(value as? String, "")
    }
}

/// Real application/core/WebKit composition. Script-message observations are
/// emitted by the executing page/world; no closure supplies a tool result,
/// authorization decision, engine acceptance or input acknowledgement.
@MainActor
private final class AgentExecutionFixture: NSObject, WKScriptMessageHandler {
    // MARK: - Variables

    let application: BrowserMacApplication
    let host: WebKitShellHost
    let windows: BrowserMacWindows
    let agents: BrowserMacAgents
    let linkFixture: AgentLinkFixture
    var link: BrowserMacAgents.Link { linkFixture.link }
    let tabID: UUID
    let spaceID: UUID
    let sessionID: UUID
    private(set) var submissions: [String] = []
    private(set) var submittedInputs: Set<UUID> = []
    var stopOnFieldRead = false
    var restoreSpaceOnInput = false
    private var closed = false
    private var loadGeneration = 0
    private var expectedDocument: String?
    private var loadedDocument: String?

    var core: OdeCore { application.browser.core }
    var page: BrowserPage {
        guard let page = application.pages.residentPage(ofTab: tabID) else {
            preconditionFailure("The fixture's resident WebKit page must exist")
        }
        return page
    }
    var webView: WKWebView {
        guard let view = page.webKitView else { preconditionFailure("The fixture must stay on WebKit") }
        return view
    }

    // MARK: - Initializers

    init(name: String = "Execution fixture") throws {
        let application = try BrowserMacApplication()
        let host = WebKitShellHost()
        let windows = BrowserMacWindows(application: application, engineHost: host)
        self.application = application
        self.host = host
        self.windows = windows
        agents = BrowserMacAgents(application: application, windows: windows)
        let core = application.browser.core
        let sessionID = UUID()
        self.sessionID = sessionID
        let space = try XCTUnwrap(application.browser.shownSpace)
        spaceID = space.id
        tabID = try XCTUnwrap(
            application.browser.openNewTab(url: try XCTUnwrap(URL(string: "about:blank")), in: space.id))
        let identity = AgentIdentity(teamID: nil, signingID: nil, path: "/fixture/execution-agent", client: nil)
        try core.send(SetAgents(isOn: true))
        try core.send(SetAgentScripts(runsScripts: true))
        try core.send(AllowAgentSpace(spaceID: space.id, allowed: true))
        try core.send(ApproveAgent(agent: ApprovedAgent(identity: identity, name: name)))
        try core.send(BeginAgentSession(sessionID: sessionID, identity: identity, name: name))
        linkFixture = try AgentLinkFixture(sessionID: sessionID)
        super.init()
        application.pages.present(tab: tabID, in: space.id)
    }

    // MARK: - Actions - Pages

    func load() async throws {
        let controller = webView.configuration.userContentController
        controller.add(self, contentWorld: .page, name: "agentExecution")
        controller.add(self, contentWorld: WebKitPageAgents.agentWorld, name: "agentExecution")
        // Observe DOM input in the isolated agent world, forwarding the actual
        // event unchanged rather than supplying an input result.
        controller.addUserScript(
            WKUserScript(
                source: """
                    const dispatch = EventTarget.prototype.dispatchEvent;
                    EventTarget.prototype.dispatchEvent = function(event) {
                      if (event.type === 'keydown' || event.type === 'beforeinput') {
                        webkit.messageHandlers.agentExecution.postMessage('input');
                      }
                      return dispatch.call(this, event);
                    };
                    """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: WebKitPageAgents.agentWorld))
        // Both readiness phases share the original five-second budget.
        let deadline = ContinuousClock.now + .seconds(5)
        // Let the application's initial about:blank finish before taking the
        // baseline. Its completion must never acknowledge the fixture load.
        try await waitUntil(deadline: deadline) {
            self.page.completedNavigationCount > 0 && self.page.activeNavigation == nil
                && !self.webView.isLoading && !self.page.live.isLoading && self.page.live.pendingURL == nil
        }
        let completedBeforeLoad = page.completedNavigationCount
        let document = UUID().uuidString
        expectedDocument = document
        loadedDocument = nil
        loadGeneration += 1
        probe("document-load-start")
        // Focus is explicit below; a deferred autofocus must not undo a test's
        // deliberate blur and turn a negative input receipt into a delivery.
        let navigation = webView.loadHTMLString(
            """
            <title>Execution fixture</title><input>
            <script>
            window.addEventListener('load', () => {
              webkit.messageHandlers.agentExecution.postMessage({ loadedDocument: '\(document)' });
            }, { once: true });
            </script>
            """, baseURL: nil)
        _ = try XCTUnwrap(navigation, "WebKit must accept the fixture document")
        probe("document-load-submitted", navigationSubmitted: navigation != nil)
        do {
            probe("readiness-start")
            try await waitUntil(deadline: deadline) {
                self.loadedDocument == document && self.page.completedNavigationCount > completedBeforeLoad
                    && self.page.activeNavigation == nil && !self.webView.isLoading
                    && !self.page.live.isLoading && self.page.live.pendingURL == nil
            }
            probe("readiness-complete")
        } catch {
            probe("readiness-error", error: error)
            throw error
        }
        do {
            probe("focus-start")
            _ = try await webView.evaluateJavaScript("document.querySelector('input').focus()")
            probe("focus-complete")
        } catch {
            probe("focus-error", error: error)
            throw error
        }
    }

    // Temporary CI attribution only: never include identifiers, script values or error descriptions.
    func probe(
        _ phase: StaticString, stopsTab: Bool = false, runsScript: Bool = false,
        navigationSubmitted: Bool = false, error: Error? = nil
    ) {
        guard ProcessInfo.processInfo.environment["ODE_NATIVE_CI_DIAGNOSTICS"] == "1" else { return }
        print(
            "ODE_NATIVE_CI agent phase=\(phase) generation=\(loadGeneration) "
                + "committed=\(page.committedNavigationCount) completed=\(page.completedNavigationCount) "
                + "loading=\(page.live.isLoading) pending=\(page.live.pendingURL != nil) "
                + "webLoading=\(webView.isLoading) held=\(link.heldPages[tabID] != nil) "
                + "cancelled=\(Task.isCancelled) stopsTab=\(stopsTab) runsScript=\(runsScript) "
                + "navigationSubmitted=\(navigationSubmitted)")
        if let error {
            let native = error as NSError
            print("ODE_NATIVE_CI agent errorDomain=\(native.domain) errorCode=\(native.code)")
        }
    }

    func perform(_ tool: BrowserAgentTool, arguments: [String: AgentJSON]) async -> AgentToolResult {
        var arguments = arguments
        arguments["tab"] = .string(tabID.uuidString)
        do throws(BrowserAgentFailure) {
            return try await tool.perform(
                BrowserAgentCall(agents: agents, link: link, sessionID: sessionID, arguments: .object(arguments)))
        } catch {
            return error.result
        }
    }

    func lateInputAcknowledgement(for inputID: UUID) async -> PageInputDelivered? {
        let engine = page.enginePage
        return await withCheckedContinuation { continuation in
            engine.agentWaits.wait(forInput: inputID, continuation)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                engine.agentWaits.expire(inputID)
            }
        }
    }

    func revoke(stopsTab: Bool) throws {
        if stopsTab {
            try core.send(StopAgentTab(tabID: tabID))
        } else {
            try core.send(AllowAgentSpace(spaceID: spaceID, allowed: false))
        }
    }

    func isClaimed() throws -> Bool {
        try core.query(AgentReach(sessionID: sessionID)).spaces.flatMap(\.tabs)
            .first { $0.tabID == tabID }?.claimed ?? false
    }

    func waitUntil(deadline: ContinuousClock.Instant? = nil, _ condition: () -> Bool) async throws {
        let deadline = deadline ?? ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "Timed out waiting for the real engine/core state")
        guard condition() else { throw BrowserAgentFailure.timedOut }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.frameInfo.isMainFrame, message.world == .page,
            let receipt = message.body as? [String: String],
            let document = receipt["loadedDocument"], document == expectedDocument
        {
            loadedDocument = document
            return
        }
        guard let submission = message.body as? String else { return }
        if submission == "input" {
            // One request may dispatch several events, such as Enter's
            // keydown and beforeinput. Observe the real request identity,
            // never count those events as separate engine submissions.
            let pending = page.enginePage.agentWaits.inputs.keys
            XCTAssertEqual(pending.count, 1, "Each observed event must belong to the real pending input")
            guard let inputID = pending.first, submittedInputs.insert(inputID).inserted else { return }
        }
        submissions.append(submission)
        do {
            if submission == "field", stopOnFieldRead { try revoke(stopsTab: true) }
            if submission == "input", restoreSpaceOnInput {
                try revoke(stopsTab: false)
                try core.send(AllowAgentSpace(spaceID: spaceID, allowed: true))
            }
        } catch { XCTFail("Core revocation failed: \(error)") }
    }

    // MARK: - Actions - Lifecycle

    func close() {
        guard !closed else { return }
        closed = true
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "agentExecution", contentWorld: .page)
        controller.removeScriptMessageHandler(forName: "agentExecution", contentWorld: WebKitPageAgents.agentWorld)
        linkFixture.close()
        application.pages.reconcile(validTabIDs: [])
        withExtendedLifetime(host) {}
    }
}
