import Foundation

extension BrowserMacAgents {
    // MARK: - Types

    private struct CapabilityQuery: Decodable {
        let tab: UUID?
    }

    // MARK: - Actions - Discovery

    /// Does not claim, load, observe or render any page. A requested tab must
    /// already be visible through this session's current core reach.
    func sessionCapabilities(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let query = try call.arguments(CapabilityQuery.self)
        let reach = try reach(call)
        var residentIsWebKit: Bool?
        if let tabID = query.tab {
            guard reach.spaces.contains(where: { $0.tabs.contains { $0.tabID == tabID } }) else {
                throw .rejected(.agentTabUnavailable(AgentTabUnavailable(tabID: tabID)))
            }
            residentIsWebKit = application.pages.residentPage(ofTab: tabID).map { $0.webKitView != nil }
        }
        let boundary = Self.supportsAgentPage(
            residentIsWebKit: residentIsWebKit, engines: core.state.engines?.engines.map(\.kind) ?? [])
        let rosterBoundary = Self.supportsAgentPage(
            residentIsWebKit: nil, engines: core.state.engines?.engines.map(\.kind) ?? [])
        let tools = BrowserAgentTool.all.map { tool in
            let failure = tool.refusal(
                pageBoundary: tool.definition.targetsExistingTab ? boundary : rosterBoundary,
                scriptsAllowed: core.state.agentPreferences.runsScripts)
            return AgentToolAvailability(
                name: tool.definition.name, eligible: failure == nil, refusal: failure?.refusal)
        }
        return .data(
            AgentSessionCapabilities(
                session: call.sessionID, tab: query.tab, allowedSpaces: reach.spaces.count,
                lockedSpaces: reach.spaces.filter(\.isLocked).count, tools: tools,
                eligibilityScope: .engineAndScriptPolicy,
                cancellation: .cooperativeNoRollback, submittedEffectsMayContinue: true,
                authorizationRecheckedOnEveryCall: true),
            note: "Eligibility covers current engine/script policy, not authorization or tested website success. "
                + "Origin, document type, tab placement, page readiness and input targets still need per-call validation. "
                + "Eligibility may change after navigation, engine changes, locking or revocation. "
                + "Cancellation cannot undo or stop already submitted engine effects.")
    }
}
