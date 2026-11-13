import Foundation

/// Answers the questions the core asks about the downloads engines run,
/// whichever engine runs them: where each file goes, and whether to go on
/// with one the core or its engine judged dangerous. A download from a tab an
/// agent session holds is never saved without the person: they approve it
/// first, in a question that names the agent. One follows each core, or one
/// each browsing mode whose Spaces it claims.
@MainActor
final class BrowserDownloadPrompts {
    // MARK: - Types

    /// Asks the person whether to go on with the download `asked` is about,
    /// until the dismissal closes the question.
    typealias Approve = @MainActor (_ asked: DownloadApprovalAsked, _ dismissal: BrowserPromptDismissal) async -> Bool

    // MARK: - Variables

    private(set) weak var core: OdeCore?
    /// Whether this answers for the Space a question names, or for a
    /// question that names none.
    private let claims: @MainActor (UUID?) -> Bool
    private let approve: Approve
    private let resolveDestination: BrowserDownloadCenter.DownloadDestinationChooser
    /// What closes each approval the person is shown, until the core settles it.
    private var dismissals: [UUID: BrowserPromptDismissal] = [:]
    /// The folder access each download writing into a chosen folder holds
    /// until it ends.
    var downloadFolders: [UUID: URL] = [:]
    /// The tab each download began in, until it ends.
    private var downloadTabs: [UUID: UUID] = [:]
    /// The downloads from an agent's tab the person approved, so their place
    /// is chosen without asking them again.
    private var approvedFromAgentTabs: Set<UUID> = []
    /// The tab of each approval about a download from an agent's tab that
    /// waits for the person, by its question.
    private var agentTabApprovals: [UUID: UUID] = [:]

    // MARK: - Initializers

    /// Answers `core`'s download questions about the Spaces it `claims`,
    /// asking the person with `approve` and choosing each file's place with
    /// `resolveDestination`.
    init(
        core: OdeCore,
        claims: @escaping @MainActor (UUID?) -> Bool = { _ in true },
        approve: @escaping Approve,
        resolveDestination: @escaping BrowserDownloadCenter.DownloadDestinationChooser = {
            await BrowserPlatformDownloadDirectory.resolve(suggestedFilename: $0, spaceID: $1, forcesPrompt: $2)
        }
    ) {
        self.core = core
        self.claims = claims
        self.approve = approve
        self.resolveDestination = resolveDestination
        core.followPrompts(self)
        core.followDownloads(self) { [weak self] download in
            guard !download.phase.isLive else { return }
            self?.downloadFolders.removeValue(forKey: download.id)?.stopAccessingSecurityScopedResource()
            self?.downloadTabs.removeValue(forKey: download.id)
            self?.approvedFromAgentTabs.remove(download.id)
        }
        core.followStartedDownloads(self) { [weak self] started in
            guard let self, let tabID = self.core?.state.pages[started.pageID]?.tabID else { return }
            self.downloadTabs[started.downloadID] = tabID
        }
    }

    // MARK: - Actions - Agents

    /// Whether a download from tab `tabID`, which an agent uses, waits for
    /// the person to approve it.
    func awaitsPerson(inTab tabID: UUID) -> Bool {
        agentTabApprovals.values.contains(tabID)
    }

    /// The agent session that holds the tab download `downloadID` began in,
    /// if any.
    private func agentSession(holding downloadID: UUID) -> AgentSessionState? {
        guard let core, let tabID = downloadTabs[downloadID] else { return nil }
        return core.state.agentSessions.first { $0.tabIDs.contains(tabID) }
    }

    /// `asked` as the person sees it when `agent` holds the tab its download
    /// began in: where it came from names the agent.
    private static func naming(_ agent: AgentSessionState, in asked: DownloadApprovalAsked) -> DownloadApprovalAsked {
        let source =
            asked.sourceHost.map { String(localized: "\($0), in a tab \(agent.name) uses") }
            ?? String(localized: "a tab \(agent.name) uses")
        return DownloadApprovalAsked(
            promptID: asked.promptID, downloadID: asked.downloadID, spaceID: asked.spaceID, filename: asked.filename,
            reasons: asked.reasons, warning: asked.warning, sourceHost: source)
    }

    /// Asks the person, as `approve` does, whether to go on with the download
    /// `asked` is about, which `agent` holds the tab of, until the dismissal
    /// closes the question. An approval the person gives lets the download
    /// choose its place without asking them again.
    private func askPerson(
        about asked: DownloadApprovalAsked, from agent: AgentSessionState, until dismissal: BrowserPromptDismissal
    ) async -> Bool {
        if let tabID = downloadTabs[asked.downloadID] { agentTabApprovals[asked.promptID] = tabID }
        let approved = await approve(Self.naming(agent, in: asked), dismissal)
        agentTabApprovals.removeValue(forKey: asked.promptID)
        if approved { approvedFromAgentTabs.insert(asked.downloadID) }
        return approved
    }

    // MARK: - Actions - Prompts

    /// Where a download's file goes: the Space's download folder, or where
    /// the person chooses when the Space or the engine asks for that.
    private func choose(_ asked: DownloadDestinationAsked) {
        Task { @MainActor [weak self, resolveDestination] in
            let resolution = await resolveDestination(asked.suggestedFilename, asked.spaceID, asked.forcesPrompt)
            guard let self else { return resolution.abandon() }
            resolution.answer(asked, for: self)
        }
    }

    /// Sends the person's answer to a question the core asked. An answer to a
    /// question that no longer waits changes nothing.
    func answer(_ intent: some PromptIntent) {
        _ = try? core?.send(intent)
    }
}

/// Answers a question the core asks about a download, and closes an approval
/// once the core settles it.
extension BrowserDownloadPrompts: CorePromptHost {
    /// The engine hosting the page shows its dialogs.
    func ask(_ asked: ScriptDialogAsked) {}

    /// The engine hosting the page shows its sign-in.
    func ask(_ asked: AuthenticationAsked) {}

    /// The engine hosting the page shows its permission request.
    func ask(_ asked: PermissionAsked) {}

    /// The Chromium engine reviews extension installs.
    func ask(_ asked: ExtensionInstallAsked) {}

    /// The quit preparation asks about downloads in progress.
    func ask(_ asked: QuitWithDownloadsAsked) {}

    /// A download from a tab an agent uses waits for the person's approval
    /// before its place is chosen, unless they already approved it; declining
    /// cancels it as cancelling the choice of its place does.
    func ask(_ asked: DownloadDestinationAsked) {
        guard claims(asked.spaceID) else { return }
        let dismissal = BrowserPromptDismissal()
        dismissals[asked.promptID] = dismissal
        // The tab a download began in is heard after the question about its
        // place in the same batch, so its agent is looked up once the batch
        // is applied.
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard !approvedFromAgentTabs.contains(asked.downloadID), let agent = agentSession(holding: asked.downloadID)
            else {
                dismissals.removeValue(forKey: asked.promptID)
                return choose(asked)
            }
            let approval = DownloadApprovalAsked(
                promptID: asked.promptID, downloadID: asked.downloadID, spaceID: asked.spaceID,
                filename: asked.suggestedFilename, reasons: [], warning: nil, sourceHost: nil)
            guard await askPerson(about: approval, from: agent, until: dismissal) else {
                return answer(AnswerDownloadDestination(promptID: asked.promptID, path: nil))
            }
            choose(asked)
        }
    }

    /// The approval about a download from a tab an agent uses names the agent.
    func ask(_ asked: DownloadApprovalAsked) {
        guard claims(asked.spaceID) else { return }
        let dismissal = BrowserPromptDismissal()
        dismissals[asked.promptID] = dismissal
        Task { @MainActor [weak self, approve] in
            let approved: Bool
            if let self, let agent = self.agentSession(holding: asked.downloadID) {
                approved = await self.askPerson(about: asked, from: agent, until: dismissal)
            } else {
                approved = await approve(asked, dismissal)
            }
            self?.answer(AnswerDownloadApproval(promptID: asked.promptID, approved: approved))
        }
    }

    func dismiss(_ settled: PromptSettled) {
        dismissals.removeValue(forKey: settled.promptID)?.dismiss()
    }
}
