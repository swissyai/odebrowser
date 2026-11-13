import Foundation
import Observation

/// The origins one agent session may open, as the person allowed them, and
/// the requests to open others, which wait for the person in a tab's bar. An
/// origin is a scheme, host and port, read from the address Ode would load,
/// so a decision binds to what the browser opens rather than to what the agent
/// says. Origins of tabs the agent comes to use are seen, never allowed for
/// that. What the person allowed is kept for the agent's identity in
/// `BrowserAgentOriginGrants`, so it lasts until they remove it; a session
/// whose agent has no known identity keeps it only for itself. A gate that
/// enters another session starts empty but for the agent's grants.
@Observable
@MainActor
final class BrowserAgentOriginGate {
    // MARK: - Types

    /// A request to open `origin`, shown in the bar of tab `tabID` until the
    /// person answers it. `allow` gives the person's Allow to the gate.
    struct Request: Identifiable {
        let id = UUID()
        let origin: String
        let tabID: UUID
        let allow: @MainActor () -> Void
    }

    /// The gates of the sessions under way, by session, which a tab's bar
    /// reads. It holds them weakly: a gate lasts as long as its connection.
    @Observable
    @MainActor
    final class Sessions {
        private struct Held {
            weak var gate: BrowserAgentOriginGate?
        }

        /// Popups keep the opener's tab as the approval surface, including
        /// their redirects and later script navigations while that tab is driven.
        private struct PopupSource {
            weak var gate: BrowserAgentOriginGate?
            let tabID: UUID
            let openerURL: URL?
        }

        private var gates: [UUID: Held] = [:]

        /// Ownership lasts until the person stops the agent in the tab or
        /// the connection ends. An idle timeout cannot distinguish delayed
        /// page scripts from the person's input.
        @ObservationIgnored private var driven: [UUID: Held] = [:]

        @ObservationIgnored private var popupSources: [UUID: PopupSource] = [:]

        /// The gate of session `sessionID`, while its connection lasts.
        func gate(for sessionID: UUID) -> BrowserAgentOriginGate? {
            gates[sessionID]?.gate
        }

        fileprivate func register(_ gate: BrowserAgentOriginGate, for sessionID: UUID) {
            gates = gates.filter { $0.value.gate != nil && $0.value.gate !== gate }
            gates[sessionID] = Held(gate: gate)
        }

        // MARK: - Actions - Driving

        func source(forPage pageID: UUID, inTab tabID: UUID?, current: URL?) -> (tabID: UUID, current: URL?)? {
            if let source = popupSources[pageID], source.gate != nil {
                return (source.tabID, current ?? source.openerURL)
            }
            return tabID.map { ($0, current) }
        }

        func inherit(pageID: UUID, fromTab tabID: UUID, current: URL?) {
            guard let gate = driver(of: tabID) else { return }
            popupSources = popupSources.filter { $0.value.gate != nil }
            popupSources[pageID] = PopupSource(gate: gate, tabID: tabID, openerURL: current)
        }

        /// The session claimed tab `tabID`, including its later page scripts.
        func drive(_ tabID: UUID, by gate: BrowserAgentOriginGate) {
            driven = driven.filter { $0.value.gate != nil }
            driven[tabID] = Held(gate: gate)
        }

        /// The session `gate` answers for no longer uses tab `tabID`.
        func release(_ tabID: UUID, by gate: BrowserAgentOriginGate) {
            if driven[tabID]?.gate === gate { driven[tabID] = nil }
            popupSources = popupSources.filter { $0.value.tabID != tabID || $0.value.gate !== gate }
        }

        /// Whether the page of tab `tabID`, whose document is at `current`,
        /// may go to `url`. It always may unless an agent drives the
        /// tab; then only to an address on the document's own origin or one
        /// the person allowed for the agent's session, and otherwise the
        /// person is asked in the tab's bar and the agent hears it waits.
        /// Whatever starts the navigation, a click, a form, a script or a
        /// redirect, is checked alike, at each step.
        func admits(navigationTo url: URL, inTab tabID: UUID, from current: URL?) -> Bool {
            guard let gate = driver(of: tabID) else { return true }
            guard let origin = BrowserAgentOriginGate.origin(of: url) else {
                gate.holdUnsupportedNavigation(in: tabID)
                return false
            }
            if let current, BrowserAgentOriginGate.origin(of: current) == origin { return true }
            guard !gate.allows(origin) else { return true }
            gate.hold(origin, in: tabID)
            return false
        }

        /// Whether the page of tab `tabID`, whose document is at `current`,
        /// may open a window at `url`: as `admits` answers for an
        /// address, and while an agent drives the tab never for a window
        /// without one, which the page's script could send anywhere.
        func admitsWindow(at url: URL?, inTab tabID: UUID, from current: URL?) -> Bool {
            guard let gate = driver(of: tabID) else { return true }
            guard let url, BrowserAgentOriginGate.origin(of: url) != nil else {
                gate.holdBlankWindow(in: tabID)
                return false
            }
            return admits(navigationTo: url, inTab: tabID, from: current)
        }

        private func driver(of tabID: UUID) -> BrowserAgentOriginGate? {
            driven[tabID]?.gate
        }
    }

    // MARK: - Static Variables

    static let sessions = Sessions()
    /// What a held window without an address is kept as.
    static let blankWindow = "about:blank"
    static let unsupportedNavigation = "unsupported-navigation"

    // MARK: - Variables

    /// The session the gate answers for now.
    private(set) var sessionID: UUID?
    /// The agent's identity as its approval record holds it, whose grants
    /// the gate answers with, or nil when the session has none.
    private(set) var identity: AgentIdentity?
    private(set) var allowed: Set<String> = []
    /// Origins of the tabs the agent used, which are never allowed for that.
    private(set) var seen: Set<String> = []
    /// At most one request per tab, oldest first.
    private(set) var pending: [Request] = []
    /// The origin each tab's page last tried to go to and was held, until
    /// the agent hears it.
    @ObservationIgnored private var held: [UUID: String] = [:]
    /// The tab the agent used last, whose bar shows the requests of calls
    /// that name no tab.
    private(set) var currentTab: UUID?

    // MARK: - Initializers

    /// Nonisolated, as a connection's link is, which holds its gate from the
    /// start.
    nonisolated init() {}

    // MARK: - Actions - Sessions

    /// Answers for session `sessionID` of the agent `identity` from now on,
    /// forgetting everything another session was allowed, saw or asked.
    func enter(_ sessionID: UUID, as identity: AgentIdentity?) {
        guard sessionID != self.sessionID else { return }
        self.sessionID = sessionID
        self.identity = identity
        allowed = []
        seen = []
        pending = []
        held = [:]
        currentTab = nil
        Self.sessions.register(self, for: sessionID)
    }

    // MARK: - Actions - Origins

    /// `url`'s origin as `scheme://host[:port]` in lower case, leaving out
    /// the scheme's default port, or nil unless it is http or https with a
    /// host.
    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            var host = url.host(percentEncoded: true)?.lowercased(), !host.isEmpty
        else { return nil }
        if host.contains(":"), !host.hasPrefix("[") { host = "[\(host)]" }
        let port = url.port.flatMap { $0 == (scheme == "https" ? 443 : 80) ? nil : $0 }
        return port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
    }

    /// Whether the person allowed the session to open `origin`: the agent's
    /// grants answer when its identity is known, so an origin removed in
    /// Settings is asked about again at once.
    func allows(_ origin: String) -> Bool {
        guard let identity else { return allowed.contains(origin) }
        return BrowserAgentOriginGrants.shared.isAllowed(origin, for: identity)
    }

    /// The agent uses tab `tabID`, which shows `address`: the tab is its
    /// current one, and the address's origin is seen.
    func use(_ tabID: UUID, at address: String?) {
        currentTab = tabID
        if let origin = address.flatMap(URL.init(string:)).flatMap(Self.origin(of:)), !seen.contains(origin) {
            seen.insert(origin)
        }
    }

    /// Asks the person in tab `tabID`'s bar whether the session may open
    /// `origin`, in place of what that bar asked before.
    func request(_ origin: String, in tabID: UUID) {
        guard !pending.contains(where: { $0.tabID == tabID && $0.origin == origin }) else { return }
        pending.removeAll { $0.tabID == tabID }
        pending.append(Request(origin: origin, tabID: tabID) { [weak self] in self?.allow(origin) })
    }

    /// The request tab `tabID`'s bar shows, when one waits there.
    func request(for tabID: UUID) -> Request? {
        pending.first { $0.tabID == tabID }
    }

    /// A navigation the page of tab `tabID` started while the agent drove it
    /// waits for the person: their bar asks about `origin`, and the agent's
    /// next answer about the tab says so.
    func hold(_ origin: String, in tabID: UUID) {
        request(origin, in: tabID)
        held[tabID] = origin
    }

    /// The page of tab `tabID` tried to open a window without an address
    /// while the agent drove it, which Ode blocked; the agent's next answer
    /// about the tab says so.
    func holdBlankWindow(in tabID: UUID) {
        held[tabID] = Self.blankWindow
    }

    func holdUnsupportedNavigation(in tabID: UUID) {
        held[tabID] = Self.unsupportedNavigation
    }

    /// The origin a navigation of tab `tabID` waits for the person to allow,
    /// or `blankWindow` for a window without an address Ode blocked, once,
    /// to tell the agent.
    func takeHeld(_ tabID: UUID) -> String? {
        held.removeValue(forKey: tabID)
    }

    /// The person allowed the session, and the agent from now on, to open
    /// `origin`, which answers every request for it.
    func allow(_ origin: String) {
        allowed.insert(origin)
        if let identity { BrowserAgentOriginGrants.shared.grant(origin, for: identity) }
        pending.removeAll { $0.origin == origin }
    }
}
