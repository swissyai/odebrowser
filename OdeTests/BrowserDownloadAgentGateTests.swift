import WebKit
import XCTest

@testable import Ode

/// A download from a tab an agent session holds is never saved without the
/// person: they approve it first, in a question that names the agent.
final class BrowserDownloadAgentGateTests: XCTestCase {
    /// Records each approval the person is asked for and holds it until the
    /// test answers, and each place a file was given.
    @MainActor
    private final class Person {
        var asked: [DownloadApprovalAsked] = []
        var waiting: [CheckedContinuation<Bool, Never>] = []
        var placed: [String] = []

        func answer(_ approved: Bool) {
            waiting.removeFirst().resume(returning: approved)
        }
    }

    @MainActor
    func testADownloadFromAnAgentsTabWaitsForThePersonWhoSeesTheAgentNamed() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ode-agent-download-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try XCTUnwrap(URL(string: "https://downloads.ode.test/"))
        let tab = TabState.Seed(title: "Downloads", url: url, placement: .current)
        let space = SpaceState.Seed(name: "Work", tabs: [tab])
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let core = browser.core

        // Claude, allowed in the Space, holds the tab.
        let claude = AgentIdentity(
            teamID: "Q6L2SF6YDW", signingID: "com.anthropic.claude-code", path: nil, client: nil)
        let session = UUID()
        try core.send(SetAgents(isOn: true))
        try core.send(AllowAgentSpace(spaceID: space.id, allowed: true))
        try core.send(ApproveAgent(agent: ApprovedAgent(identity: claude, name: "Claude")))
        try core.send(BeginAgentSession(sessionID: session, identity: claude, name: "Claude"))
        try core.send(ClaimAgentTab(sessionID: session, tabID: tab.id))
        XCTAssertEqual(core.state.agentSessions.first?.tabIDs, [tab.id])

        let person = Person()
        let prompts = BrowserDownloadPrompts(
            core: core,
            approve: { asked, _ in
                person.asked.append(asked)
                return await withCheckedContinuation { person.waiting.append($0) }
            },
            resolveDestination: { filename, _, forcesPrompt in
                person.placed.append(filename)
                XCTAssertFalse(forcesPrompt)
                return .destination(root.appending(path: "\(UUID())-\(filename)"), securityScopedURL: nil)
            })
        let opened = try XCTUnwrap(browser.openWebKitPage(in: space.id, for: tab.id))
        let page = BrowserPage(
            corePage: opened.core, webKitPage: opened.webKit, dialogPresenter: BrowserDialogPresenter(),
            downloadCenter: BrowserDownloadCenter(core: core),
            permissionCenter: BrowserSitePermissionCenter(core: core),
            spaceID: space.id, profileID: space.profileID, spaceName: space.settings.name)
        defer {
            page.release(keepingState: false)
            withExtendedLifetime(prompts) {}
        }
        let web = page.webView

        /// Loads a fresh document, so each file is the site's first, and
        /// follows its download link.
        func download() async throws {
            web.loadSimulatedRequest(
                URLRequest(url: url),
                responseHTML: """
                    <title>Downloads</title>
                    <a id="file" href="data:text/plain;base64,aGVsbG8=" download="agent.txt">agent.txt</a>
                    """)
            try await waitUntil(timeout: .seconds(5)) { web.url == url && !web.isLoading }
            _ = try await web.callAsyncJavaScript(
                "document.getElementById('file').click();", arguments: [:], in: nil, contentWorld: .page)
        }
        func phases() -> [DownloadPhase] { core.state.downloads.map(\.phase) }

        // Declined: the question names the agent, and nothing is placed or saved.
        try await download()
        try await waitUntil(timeout: .seconds(5)) { person.asked.count == 1 }
        XCTAssertEqual(person.asked[0].filename, "agent.txt")
        XCTAssertTrue(person.asked[0].sourceHost?.contains("Claude") ?? false)
        XCTAssertTrue(prompts.awaitsPerson(inTab: tab.id))
        XCTAssertTrue(person.placed.isEmpty)
        person.answer(false)
        try await waitUntil(timeout: .seconds(5)) { phases() == [.canceled] }
        XCTAssertFalse(prompts.awaitsPerson(inTab: tab.id))
        XCTAssertTrue(person.placed.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)

        // Approved: the file gets its place without a second question.
        try await download()
        try await waitUntil(timeout: .seconds(5)) { person.asked.count == 2 }
        XCTAssertTrue(person.placed.isEmpty)
        person.answer(true)
        try await waitUntil(timeout: .seconds(5)) { phases().first == .finished }
        XCTAssertEqual(person.asked.count, 2)
        XCTAssertEqual(person.placed, ["agent.txt"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
    }
}
