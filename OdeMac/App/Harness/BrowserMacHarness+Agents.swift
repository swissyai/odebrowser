#if DEBUG || ODE_REVIEW_BUILD

    import AppKit

    /// The harness's agent commands: let one program use Ode's agent tools in
    /// this isolated launch without the question the person answers, which
    /// would bring Ode forward, so a run can drive the bundled helper with
    /// nobody at the Mac.
    extension BrowserMacHarness {
        // MARK: - Actions - Agents

        /// Turns agents on, lets them reach every Space of the window's
        /// session and allows the unsigned program at `path`, as Ode knows a
        /// program its developer didn't sign, under `name`. Answers whether the
        /// agent socket listens yet; it opens a moment after agents turn on.
        func allowAgent(_ arguments: [String: Any]) throws -> [String: Any] {
            guard let path = arguments["path"] as? String, path.hasPrefix("/") else {
                throw Failure(description: "allowAgent needs the absolute path of the agent program")
            }
            let browser = try context().browser
            let core = browser.core
            _ = try core.send(SetAgents(isOn: true))
            for space in browser.spaceModels {
                _ = try core.send(AllowAgentSpace(spaceID: space.id, allowed: true))
            }
            let identity = AgentIdentity(teamID: nil, signingID: nil, path: path, client: nil)
            let name = arguments["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent
            _ = try core.send(ApproveAgent(agent: ApprovedAgent(identity: identity, name: name)))
            return ["listening": shell.application?.agentEndpoint.state == .listening]
        }
    }

#endif
