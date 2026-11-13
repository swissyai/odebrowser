import SwiftUI

/// The bar a page wears while an agent uses its tab: the agent's mark in its
/// colour, who uses the tab, Show Activity, which opens what agents did in
/// Settings › Agents, and Stop, which keeps the agent out of the tab for as
/// long as it stays connected. While the agent asks to open a site the person
/// hasn't allowed it, the bar asks instead, with Allow and Stop. It sits where
/// the engine's own bars do, in the same glass.
struct BrowserAgentPageBar: View {
    @Environment(\.browserMacWindows) private var windows
    let session: AgentSessionState
    /// The tab the bar sits on, whose requests it shows.
    var tabID: UUID? = nil
    let stop: () -> Void

    /// The agent's request to open a site, waiting in this tab, when one does.
    private var request: BrowserAgentOriginGate.Request? {
        tabID.flatMap { BrowserAgentOriginGate.sessions.gate(for: session.sessionID)?.request(for: $0) }
    }

    var body: some View {
        HStack(spacing: BrowserWebPageSurfaceMetrics.infoBarSpacing) {
            Image(systemName: "sparkles")
                .foregroundStyle((session.color ?? .agentDefault).color)
                .accessibilityHidden(true)
            if let request {
                Text(
                    "\(session.name) wants to open \(request.origin)",
                    comment: "The bar on a page whose agent asks to open a site the person hasn't allowed it."
                )
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(String(localized: "Allow"), action: request.allow)
            } else {
                Text("\(session.name) is using this tab", comment: "The bar on a page an agent uses.")
                    .font(.callout)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(
                    String(localized: "Show Activity", comment: "Opens what agents did in Settings."),
                    action: showActivity)
            }
            Button(String(localized: "Stop", comment: "Stops the agent using a tab."), action: stop)
        }
        .controlSize(.small)
        .padding(.horizontal, BrowserWebPageSurfaceMetrics.infoBarHorizontalPadding)
        .padding(.vertical, BrowserWebPageSurfaceMetrics.infoBarVerticalPadding)
        .frame(maxWidth: BrowserWebPageSurfaceMetrics.infoBarMaximumWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: BrowserWebPageSurfaceMetrics.infoBarCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BrowserWebPageSurfaceMetrics.infoBarCornerRadius)
                .strokeBorder((session.color ?? .agentDefault).color, lineWidth: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent-page-bar")
    }

    /// Opens Settings › Agents in the window the person uses, as the command
    /// palette opens a Settings page, with the activity in view.
    private func showActivity() {
        guard let window = windows?.activeWindowModel, let space = window.browser.shownSpace else { return }
        BrowserAgentActivityLog.shared.isRevealRequested = true
        window.spaceSettingsPresentation.present(.agents, assignment: BrowserSpaceRuntimeAssignment(space: space))
        window.browser.openSettings()
        window.pages.select()
    }
}
