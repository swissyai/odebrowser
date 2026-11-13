import AppKit
import XCTest

@testable import Ode

/// Capability refusals must not give an agent ownership of a tab. The real
/// core still decides reach, locked/private boundaries and stopped-tab errors.
@MainActor
final class BrowserAgentClaimTests: XCTestCase {
    // MARK: - Actions - Claims

    func testUnsupportedPageCallsLeaveClaimsUntouchedAndPreserveCoreRejections() async throws {
        let application = try BrowserMacApplication()
        let host = WebKitShellHost()
        let windows = BrowserMacWindows(application: application, engineHost: host)
        let agents = BrowserMacAgents(application: application, windows: windows)
        let core = application.browser.core
        let space = try XCTUnwrap(application.browser.shownSpace)
        let originalRoster = try XCTUnwrap(core.state.engines)
        let blank = try XCTUnwrap(URL(string: "about:blank"))
        defer {
            EnginesChanged(roster: originalRoster).apply(to: core.state)
            application.pages.reconcile(validTabIDs: [])
            withExtendedLifetime(host) {}
        }
        let identity = AgentIdentity(teamID: nil, signingID: nil, path: "/fixture/agent", client: nil)
        let first = UUID()
        let second = UUID()
        try core.send(SetAgents(isOn: true))
        try core.send(AllowAgentSpace(spaceID: space.id, allowed: true))
        try core.send(ApproveAgent(agent: ApprovedAgent(identity: identity, name: "Fixture")))
        for session in [first, second] {
            try core.send(BeginAgentSession(sessionID: session, identity: identity, name: "Fixture"))
        }
        let fixture = try AgentLinkFixture(sessionID: first)
        defer { fixture.close() }
        let link = fixture.link

        // Advertise the roster at the same read-model boundary as an engine
        // registration. No Chromium process, network or native input is needed.
        let cases: [(engines: [EngineKind]?, resident: Bool, unsupported: Bool)] = [
            ([.chromium], false, false), ([.webKit, .chromium], false, false),
            ([], false, false), (nil, false, false), ([.webKit, .chromium], true, false),
            ([.webKit], true, true),
        ]
        for (index, scenario) in cases.enumerated() {
            EnginesChanged(roster: originalRoster).apply(to: core.state)
            let tabID = try XCTUnwrap(
                application.browser.openNewTab(url: blank, in: space.id, selecting: false))
            var originalPage: BrowserPage?
            if scenario.resident {
                application.pages.present(tab: tabID, in: space.id)
                let page = try XCTUnwrap(application.pages.residentPage(ofTab: tabID))
                XCTAssertNotNil(page.webKitView)
                if scenario.unsupported {
                    originalPage = page
                    let replacement = BrowserPage(
                        corePage: page.corePage, engine: UnsupportedAgentPageAdapter(page.engineAdapter),
                        dialogPresenter: BrowserDialogPresenter(), downloadCenter: application.pages.downloadCenter,
                        permissionCenter: application.pages.permissionCenter,
                        spaceID: space.id, profileID: space.profileID, spaceName: space.settings.name,
                        allowsCredentialAccess: false)
                    application.pages.runtimeStore.runtimes[tabID]?.page = replacement
                    XCTAssertNil(application.pages.residentPage(ofTab: tabID)?.webKitView)
                }
            }
            defer {
                if let originalPage { application.pages.runtimeStore.runtimes[tabID]?.page = originalPage }
            }
            if let kinds = scenario.engines {
                EnginesChanged(
                    roster: EngineRoster(
                        engines: kinds.map { EngineState(kind: $0, capabilities: [], isDefault: $0 == kinds.first) },
                        offered: [], badged: [])
                ).apply(to: core.state)
            } else {
                core.state.engines = nil
            }
            let call = BrowserAgentCall(
                agents: agents, link: link, sessionID: first,
                arguments: .object(["tab": .string(tabID.uuidString)]))
            func reached(_ session: UUID) throws -> AgentTab {
                try XCTUnwrap(
                    core.query(AgentReach(sessionID: session)).spaces.flatMap(\.tabs).first { $0.tabID == tabID })
            }
            XCTAssertFalse(try reached(first).claimed)
            let discovery = try await BrowserAgentTool.sessionCapabilities.perform(call)
            let capabilities = try XCTUnwrap(discovery.structuredContent.data).decoded(
                as: AgentSessionCapabilities.self)
            XCTAssertEqual(capabilities.session, first)
            XCTAssertEqual(capabilities.tab, tabID)
            XCTAssertEqual(capabilities.cancellation, .cooperativeNoRollback)
            XCTAssertEqual(capabilities.eligibilityScope, .engineAndScriptPolicy)
            XCTAssertTrue(capabilities.submittedEffectsMayContinue)
            let opening = try XCTUnwrap(capabilities.tools.first { $0.name == AgentToolDefinition.openTab.name })
            XCTAssertEqual(
                opening.eligible, scenario.engines == [.webKit],
                "Opening a new tab does not use the queried resident page")
            let snapshot = try XCTUnwrap(capabilities.tools.first { $0.name == AgentToolDefinition.takeSnapshot.name })
            XCTAssertFalse(snapshot.eligible)
            XCTAssertEqual(snapshot.refusal, .navigationBoundaryUnavailable)
            let screenshot = try XCTUnwrap(capabilities.tools.first { $0.name == AgentToolDefinition.screenshot.name })
            XCTAssertFalse(screenshot.eligible)
            XCTAssertEqual(screenshot.refusal, .screenshotRedactionUnavailable)
            XCTAssertTrue(capabilities.tools.first { $0.name == AgentToolDefinition.listTabs.name }?.eligible == true)
            XCTAssertFalse(try reached(first).claimed, "Discovery must not claim the tab")
            XCTAssertTrue(link.drivenTabs.isEmpty)
            XCTAssertTrue(link.observedPages.isEmpty)
            do {
                _ = try await BrowserAgentTool.takeSnapshot.perform(call)
                XCTFail("Unsupported case \(index) returned page content.")
            } catch {
                XCTAssertEqual(error.message, BrowserAgentFailure.navigationBoundaryUnavailable.message)
            }
            XCTAssertFalse(try reached(first).claimed, "Refused case \(index) claimed the tab.")
            XCTAssertFalse(core.state.agentSessions.first { $0.sessionID == first }?.tabIDs.contains(tabID) ?? true)
            XCTAssertFalse(link.drivenTabs.contains(tabID))
            XCTAssertTrue(link.heldPages.isEmpty)

            // Claims are not exclusive: even the old accidental claim must not
            // be mistaken for proof that another session was blocked.
            try core.send(ClaimAgentTab(sessionID: second, tabID: tabID))
            XCTAssertTrue(try reached(second).claimed)
            try core.send(StopAgentTab(tabID: tabID))
            do {
                _ = try await BrowserAgentTool.takeSnapshot.perform(call)
                XCTFail("A stopped tab must stay stopped, even with an unsupported roster.")
            } catch {
                XCTAssertEqual(
                    error.message,
                    BrowserAgentFailure.rejected(.agentTabStopped(AgentTabStopped(tabID: tabID))).message)
            }
        }

        EnginesChanged(roster: originalRoster).apply(to: core.state)
        let availableTab = try XCTUnwrap(application.browser.openNewTab(url: blank, in: space.id))
        let admittedCall = BrowserAgentCall(agents: agents, link: link, sessionID: first, arguments: .object([:]))
        let discovery = try await BrowserAgentTool.sessionCapabilities.perform(admittedCall)
        let capabilities = try XCTUnwrap(discovery.structuredContent.data).decoded(as: AgentSessionCapabilities.self)
        XCTAssertTrue(capabilities.tools.first { $0.name == AgentToolDefinition.takeSnapshot.name }?.eligible == true)
        XCTAssertFalse(capabilities.tools.first { $0.name == AgentToolDefinition.screenshot.name }?.eligible ?? true)
        let (_, admitted) = try agents.claim(availableTab, admittedCall)
        XCTAssertEqual(admitted.id, availableTab)
        XCTAssertEqual(core.state.agentSessions.first { $0.sessionID == first }?.tabIDs, [availableTab])
        XCTAssertTrue(link.drivenTabs.contains(availableTab))
        try core.send(StopAgentTab(tabID: availableTab))
        BrowserAgentOriginGate.sessions.release(availableTab, by: link.gate)
        link.drivenTabs.remove(availableTab)

        // An unsupported roster must not reveal private, unallowed or missing
        // tabs through a different error, or change any session's ownership.
        let privateTab = try XCTUnwrap(application.privateBrowser.openNewTab(url: blank))
        let deniedTab = try XCTUnwrap(application.browser.openNewTab(url: blank, in: space.id))
        EnginesChanged(
            roster: EngineRoster(
                engines: [EngineState(kind: .chromium, capabilities: [], isDefault: true)], offered: [], badged: [])
        ).apply(to: core.state)
        application.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: space.id)
        let lockedCall = BrowserAgentCall(
            agents: agents, link: link, sessionID: first,
            arguments: .object(["tab": .string(deniedTab.uuidString)]))
        do {
            _ = try await BrowserAgentTool.takeSnapshot.perform(lockedCall)
            XCTFail("A locked tab was offered to an agent.")
        } catch {
            XCTAssertEqual(
                error.message,
                BrowserAgentFailure.rejected(.agentTabUnavailable(AgentTabUnavailable(tabID: deniedTab))).message)
        }
        try core.send(AllowAgentSpace(spaceID: space.id, allowed: false))
        for tabID in [privateTab, deniedTab, UUID()] {
            let call = BrowserAgentCall(
                agents: agents, link: link, sessionID: first,
                arguments: .object(["tab": .string(tabID.uuidString)]))
            do {
                _ = try await BrowserAgentTool.sessionCapabilities.perform(call)
                XCTFail("Discovery revealed an unreachable tab")
            } catch {
                XCTAssertEqual(
                    error.message,
                    BrowserAgentFailure.rejected(.agentTabUnavailable(AgentTabUnavailable(tabID: tabID))).message)
            }
            do {
                _ = try await BrowserAgentTool.takeSnapshot.perform(call)
                XCTFail("An unreachable tab was offered to an agent.")
            } catch {
                XCTAssertEqual(
                    error.message,
                    BrowserAgentFailure.rejected(.agentTabUnavailable(AgentTabUnavailable(tabID: tabID))).message)
            }
        }
        XCTAssertTrue(core.state.agentSessions.allSatisfy { $0.tabIDs.isEmpty })
    }
}

/// A resident host without the trusted WebKit adapter. It borrows only the
/// existing blank page's engine ports; it never creates or launches an engine.
@MainActor
private final class UnsupportedAgentPageAdapter: BrowserPageEngineAdapter {
    // MARK: - Variables

    let engine: any BrowserPageEngine
    let enginePage: EnginePage
    let linkHover: BrowserLinkHoverController? = nil
    let linkDrag: BrowserLinkDragController? = nil
    let pictureInPicture: (any BrowserPagePictureInPictureController)? = nil
    let readerModeSession: BrowserReaderModeSession? = nil
    let faviconSession: BrowserFaviconSession? = nil
    let isContentBlockingActive = false
    let reporter: EnginePageReporter? = nil
    let credentialEvaluator: BrowserCredentialSession.Evaluate? = nil
    let translationDocument: BrowserTranslationDocument? = nil
    let previewDocument: BrowserTabPreviewDocument? = nil
    let passwordExtension: String? = nil
    let holdsNavigationsUntilPainted = false
    let reportsPaints = false

    // MARK: - Initializers

    init(_ adapter: any BrowserPageEngineAdapter) {
        engine = adapter.engine
        enginePage = adapter.enginePage
    }

    // MARK: - Actions - Hosting

    func askDocument() async {}
    func pauseMedia() {}
    func makeMediaSessionCoordinator(
        for page: BrowserPage, store: BrowserMediaSessionStore
    ) -> BrowserMediaSessionPageCoordinator? { nil }
    func attach(to page: BrowserPage, allowsCredentialAccess: Bool) {}
    func detach(from page: BrowserPage) {}
    func makeBoostDocument(
        receive: @escaping @MainActor (BrowserBoostPageMessage) -> Void
    ) -> (any BrowserBoostDocument)? { nil }
    func install(_ focusRestoration: BrowserWebFocusRestorationController) {}
    func monitorUserActivity(for page: BrowserPage) {}
    func observePaints(for page: BrowserPage) {}
    func styleVisitedLinks(history: [HistoryEntryState]) async {}
    func prepareForNavigation() {}
    func sitePermissionDidChange(_ permission: SitePermission, on page: BrowserPage) {}
    func setPrivateBrowsing(_ isPrivate: Bool) {}
}
