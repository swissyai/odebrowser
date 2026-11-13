import AppKit
import SwiftUI

/// Whether agents the person runs on this Mac, such as coding agents, may use
/// Ode; how to connect one; which of the person's Spaces agents reach;
/// whether agents may run scripts in pages; the agents connected now and
/// allowed before, with the sites each may open; and what agents did.
struct BrowserAgentsSettingsPane: View {
    // MARK: - Static Variables

    /// How many of the newest activity entries the pane lists.
    private static let activityCount = 200
    /// The row Show Activity brings into view.
    private static let activityID = "agent-activity"

    // MARK: - Variables

    let core: OdeCore
    @Environment(BrowserAgentEndpointStatus.self) private var endpoint: BrowserAgentEndpointStatus?
    @State private var failure: String?
    /// The agents whose Connect is running.
    @State private var connecting: Set<BrowserAgentCommand> = []
    /// How each Connect went, until the pane appears again.
    @State private var connections: [BrowserAgentCommand: BrowserAgentConnector.Outcome] = [:]

    private var preferences: AgentPreferences { core.state.agentPreferences }
    private var activity: BrowserAgentActivityLog { .shared }
    private var grants: BrowserAgentOriginGrants { .shared }
    private var connector: BrowserAgentConnector { .shared }
    /// The helper agents run, inside this app.
    private let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ode-browser").path
    /// Whether macOS runs this copy of Ode from a temporary place, where the
    /// helper's path changes every launch.
    private var isTranslocated: Bool { helper.contains("/AppTranslocation/") }
    /// Whether agents can reach this copy of Ode at all, so a registration
    /// naming its helper is worth making.
    private var canConnect: Bool {
        if isTranslocated { return false }
        if case .failed = endpoint?.state { return false }
        return true
    }

    /// The Spaces of the person's own session that are not being deleted,
    /// which are the only ones agents may be allowed to reach.
    private var spaces: [SpaceModel] {
        guard let workspace = core.state.workspaces.values.first(where: { $0.kind.keepsAppPreferences }) else {
            return []
        }
        let deleting = Set(workspace.spaceDeletions.map(\.spaceID))
        return workspace.spaces.models.filter { !deleting.contains($0.id) }
    }

    // MARK: - Actions - Presentation

    var body: some View {
        ScrollViewReader { proxy in
            pane
                .onAppear { connections = [:] }
                .onChange(of: activity.isRevealRequested, initial: true) { _, requested in
                    guard requested else { return }
                    activity.isRevealRequested = false
                    Task {
                        // A pane that just opened lays its rows out first.
                        try? await Task.sleep(for: .milliseconds(150))
                        withAnimation { proxy.scrollTo(Self.activityID, anchor: .top) }
                    }
                }
        }
    }

    private var pane: some View {
        BrowserSettingsPane(.agents) {
            Section {
                Toggle("Allow agents to use Ode", isOn: isOn)
                    .accessibilityIdentifier("agents-enabled")
                    .settingsSearchTarget(.allowAgents)
            } footer: {
                OdeFormFootnote(
                    "Coding agents on this Mac can read and act on tabs and history in the Spaces you choose, and open windows. Ode asks before each new agent connects."
                )
            }
            if preferences.isOn {
                connection
                if canConnect {
                    BrowserAgentConfigFileSection(helper: helper, copy: copy)
                }
            }
            Section {
                ForEach(spaces) { space in
                    Toggle(isOn: allows(space)) {
                        BrowserSpaceIdentityLabel(space: space)
                    }
                }
            } header: {
                Text("Spaces")
            } footer: {
                OdeFormFootnote(
                    "Agents can open a private window but never reach into one, and see only the name of a locked Space."
                )
            }
            .disabled(!preferences.isOn)
            Section {
                Toggle("Let agents run scripts in pages", isOn: runsScripts)
                    .settingsSearchTarget(.agentScripts)
            } footer: {
                OdeFormFootnote("Scripts run with the page’s own access to the site.")
            }
            .disabled(!preferences.isOn)
            if !core.state.agentSessions.isEmpty {
                Section {
                    ForEach(core.state.agentSessions, id: \.sessionID) { session in
                        BrowserAgentRow(name: session.name, detail: nil, color: session.color ?? .agentDefault) {
                            Button("Disconnect") { send(EndAgentSession(sessionID: session.sessionID)) }
                        }
                    }
                    Button("Stop All Agents") { send(StopAllAgents()) }
                } header: {
                    Text("Connected")
                } footer: {
                    OdeFormFootnote(
                        "Stopping every agent disconnects it and keeps it out of the tabs it used until Ode quits.")
                }
            }
            Section {
                if preferences.agents.isEmpty {
                    Text("No agents yet").foregroundStyle(.secondary)
                }
                ForEach(Array(preferences.agents.enumerated()), id: \.offset) { _, agent in
                    BrowserAgentRow(name: agent.name, detail: Self.detail(of: agent.identity), color: nil) {
                        Button("Forget") { forget(agent.identity) }
                    }
                    ForEach(grants.origins(for: agent.identity), id: \.self) { origin in
                        BrowserAgentSiteRow(origin: origin) { grants.revoke(origin, for: agent.identity) }
                    }
                }
            } header: {
                Text("Allowed agents")
            } footer: {
                OdeFormFootnote("Forgetting an agent disconnects it. Ode asks again the next time it connects.")
            }
            activitySection
            if let failure { Text(failure).foregroundStyle(OdeColor.danger) }
        }
    }

    /// How to connect an agent, while agents are on: a line for each agent
    /// Ode knows, and Connect for those whose command is on this Mac, or why
    /// agents can't reach Ode.
    @ViewBuilder private var connection: some View {
        Section {
            if isTranslocated {
                Text("Move Ode to your Applications folder to connect agents.").foregroundStyle(.secondary)
            } else if case .failed(let failure) = endpoint?.state {
                Text(failure.message).foregroundStyle(OdeColor.danger)
            } else {
                ForEach(BrowserAgentCommand.all, id: \.self) { command in
                    LabeledContent {
                        HStack {
                            if connector.isInstalled(command) {
                                Button("Connect") { connect(command) }
                                    .disabled(connecting.contains(command))
                            }
                            Button("Copy Setup") { copy(command.line(helper: helper)) }
                        }
                    } label: {
                        Text(verbatim: command.title)
                        if !command.alsoReaches.isEmpty {
                            Text("Also reaches \(command.alsoReaches.formatted(.list(type: .and))).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let note = command.note {
                            Text(verbatim: note).font(.caption).foregroundStyle(.secondary)
                        }
                        if let outcome = connections[command] {
                            if outcome.succeeded {
                                Text("Connected").foregroundStyle(.secondary)
                            } else if outcome.output.isEmpty {
                                Text("Couldn’t connect. Use Copy Setup instead.").foregroundStyle(.red)
                            } else {
                                Text(outcome.output).foregroundStyle(.red).lineLimit(3)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Connect an Agent")
        } footer: {
            OdeFormFootnote(
                "Paste the setup in your agent’s terminal or settings. Ode must be open while the agent works.")
        }
        .task {
            await withTaskGroup(of: Void.self) { group in
                for command in BrowserAgentCommand.all {
                    group.addTask { await connector.find(command) }
                }
            }
        }
    }

    /// Runs the agent's own line through the person's login shell and keeps
    /// how it went for the row.
    private func connect(_ command: BrowserAgentCommand) {
        connecting.insert(command)
        connections[command] = nil
        Task {
            connections[command] = await connector.register(command, helper: helper)
            connecting.remove(command)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// What agents did, newest first, which stays after an agent disconnects
    /// until the person clears it.
    private var activitySection: some View {
        Section {
            Button("Clear Activity") { activity.clear() }
                .disabled(activity.entries.isEmpty)
                .id(Self.activityID)
            if activity.entries.isEmpty {
                Text("No activity yet").foregroundStyle(.secondary)
            }
            ForEach(Array(activity.entries.suffix(Self.activityCount).reversed())) { entry in
                BrowserAgentActivityRow(entry: entry)
            }
        } header: {
            Text("Activity")
        } footer: {
            OdeFormFootnote("Ode never shows what agents type or fill. Activity stays until you clear it.")
        }
    }

    /// The program that vouches for an allowed agent: where it is, or its
    /// signing identifier. An interpreter's agent is named for itself, so the
    /// interpreter shows here.
    private static func detail(of identity: AgentIdentity) -> String? {
        identity.path ?? identity.signingID
    }

    // MARK: - Actions - Preferences

    private var isOn: Binding<Bool> {
        Binding {
            preferences.isOn
        } set: {
            send(SetAgents(isOn: $0))
        }
    }

    private var runsScripts: Binding<Bool> {
        Binding {
            preferences.runsScripts
        } set: {
            send(SetAgentScripts(runsScripts: $0))
        }
    }

    private func allows(_ space: SpaceModel) -> Binding<Bool> {
        Binding {
            preferences.spaceIDs.contains(space.id)
        } set: {
            send(AllowAgentSpace(spaceID: space.id, allowed: $0))
        }
    }

    /// Forgets the agent `identity` and the sites it was allowed, so a later
    /// approval starts with none.
    private func forget(_ identity: AgentIdentity) {
        do {
            try core.send(ForgetAgent(identity: identity))
            failure = nil
            grants.revokeAll(for: identity)
        } catch { failure = error.explanation }
    }

    private func send(_ intent: some AgentIntent) {
        do {
            try core.send(intent)
            failure = nil
        } catch { failure = error.explanation }
    }
}

/// Agents that read their servers from a file they own: pick one, read the
/// entry with the helper's path filled in, copy it, show the file's folder,
/// or install it through the agent's own link. Ode never writes the file.
private struct BrowserAgentConfigFileSection: View {
    let helper: String
    let copy: (String) -> Void
    @State private var file: BrowserAgentConfigFile = .cursor

    var body: some View {
        Section {
            Picker("Agent", selection: $file) {
                ForEach(BrowserAgentConfigFile.all) { file in
                    Text(verbatim: file.title).tag(file)
                }
            }
            VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
                if let path = file.path {
                    Text(verbatim: path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: file.entry(helper: helper))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                if let note = file.note {
                    Text(verbatim: note).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Copy") { copy(file.entry(helper: helper)) }
                if file.isFolderPresent {
                    Button("Open Config Folder") { reveal(file) }
                }
                if let link = file.installLink(helper: helper) {
                    Button("Install in \(file.title)") { NSWorkspace.shared.open(link) }
                }
            }
        } header: {
            Text("Add to a Config File")
        } footer: {
            OdeFormFootnote("Paste the entry into the agent’s file. Ode never edits these files itself.")
        }
    }

    /// Shows the file in its folder, or the folder alone while the file
    /// doesn't exist yet.
    private func reveal(_ file: BrowserAgentConfigFile) {
        guard let url = file.fileURL else { return }
        if file.isFilePresent {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

/// An agent: its name, what tells it apart, the colour it wears while
/// connected, and what the person can do about it.
private struct BrowserAgentRow<Action: View>: View {
    let name: String
    let detail: String?
    let color: BrandColor?
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack {
            if let color {
                Image(systemName: "sparkles")
                    .foregroundStyle(color.color)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading) {
                Text(name)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            action()
        }
    }
}

/// A site an allowed agent may open without asking, and Remove, after which
/// Ode asks again the next time the agent opens it.
private struct BrowserAgentSiteRow: View {
    let origin: String
    let remove: () -> Void

    var body: some View {
        HStack {
            Text(origin)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Remove", action: remove)
                .accessibilityLabel(Text("Remove \(origin)"))
        }
        .padding(.leading)
    }
}

/// One call an agent made: when, the agent in its colour, the tool, the tab
/// it named, what it asked, and how it went.
private struct BrowserAgentActivityRow: View {
    let entry: BrowserAgentActivityLog.Entry

    /// The tab's title, or its address when it has none.
    private var tab: String? {
        [entry.tabTitle, entry.tabURL].compactMap { $0 }.first { !$0.isEmpty }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle((entry.agentColor ?? .agentDefault).color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.agentName)
                    Text(entry.tool).font(.callout.monospaced())
                    Spacer()
                    Text(entry.time, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let tab {
                    Text(tab)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                switch entry.outcome {
                case .ok:
                    Text("OK").font(.caption).foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview("Agent rows") {
        Form {
            BrowserAgentRow(name: "Claude", detail: nil, color: BrandColor(red: 0.85, green: 0.47, blue: 0.34)) {
                Button("Disconnect") {}
            }
            BrowserAgentRow(name: "claude", detail: "com.anthropic.claude-code", color: nil) { Button("Forget") {} }
            BrowserAgentSiteRow(origin: "https://example.com") {}
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }
#endif
