import Foundation
import Observation

/// The origins the person allowed each approved agent to open, by the agent's
/// identity as the core's approval records keep it rather than by its
/// session, so what they allowed outlasts the connection and a relaunch. The
/// grants are kept in the app's own Application Support directory, beside the
/// activity log, until the person removes them in Settings › Agents. Only the
/// person's Allow adds an origin: nothing here is granted ahead of them.
@Observable
@MainActor
final class BrowserAgentOriginGrants {
    // MARK: - Static Variables

    static let shared = BrowserAgentOriginGrants(file: storageFile(for: .current))
    static let fileName = "origin-grants.json"

    /// How long the grants wait after a change before writing, so several
    /// changes write once.
    private static let saveDelay: Duration = .seconds(1)

    // MARK: - Types

    /// An agent's identity as its approval record holds it: its team and
    /// signing identifier, or its path, and the name an interpreter's agent
    /// gives.
    struct Key: Codable, Hashable, Sendable {
        let teamID: String?
        let signingID: String?
        let path: String?
        let client: String?

        init(_ identity: AgentIdentity) {
            teamID = identity.teamID
            signingID = identity.signingID
            path = identity.path
            client = identity.client
        }
    }

    /// One agent's allowed origins, as the file keeps them.
    private struct Record: Codable, Sendable {
        let agent: Key
        let origins: [String]
    }

    // MARK: - Variables

    /// The allowed origins of each agent; an agent with none has no entry.
    private(set) var grants: [Key: Set<String>] = [:]

    /// The file the grants are kept in, or none when this launch keeps them
    /// in memory.
    @ObservationIgnored private let store: BrowserAgentFileStore<[Record]>

    // MARK: - Initializers

    init(file: URL?) {
        store = BrowserAgentFileStore(
            file: file, name: "Agent origin grants", queueLabel: "origin-grants", saveDelay: Self.saveDelay)
        store.load(
            restore: { [weak self] stored in self?.restore(stored ?? []) },
            snapshot: { [weak self] in self?.records })
    }

    /// The grants' file for `environment`: the installed app's, or the one a
    /// persistent review launch keeps apart from it. Nil keeps the grants in
    /// memory.
    static func storageFile(for environment: BrowserLaunchEnvironment) -> URL? {
        BrowserAgentFileStore<[Record]>.file(named: fileName, for: environment)
    }

    // MARK: - Actions - Grants

    /// The person allowed the agent `identity` to open `origin`.
    func grant(_ origin: String, for identity: AgentIdentity) {
        let key = Key(identity)
        guard grants[key]?.contains(origin) != true else { return }
        grants[key, default: []].insert(origin)
        scheduleSave()
    }

    /// The person no longer allows the agent `identity` to open `origin`, so
    /// it is asked about again.
    func revoke(_ origin: String, for identity: AgentIdentity) {
        let key = Key(identity)
        guard grants[key]?.remove(origin) != nil else { return }
        if grants[key]?.isEmpty == true { grants[key] = nil }
        scheduleSave()
    }

    /// Removes every origin the agent `identity` was allowed, as when the
    /// person forgets the agent.
    func revokeAll(for identity: AgentIdentity) {
        guard grants.removeValue(forKey: Key(identity)) != nil else { return }
        scheduleSave()
    }

    /// The origins the agent `identity` may open, in order.
    func origins(for identity: AgentIdentity) -> [String] {
        (grants[Key(identity)] ?? []).sorted()
    }

    /// Whether the person allowed the agent `identity` to open `origin`.
    func isAllowed(_ origin: String, for identity: AgentIdentity) -> Bool {
        grants[Key(identity)]?.contains(origin) == true
    }

    // MARK: - Actions - Storage

    /// Adds the stored grants to those made while they were read.
    private func restore(_ stored: [Record]) {
        let added = grants
        var restored: [Key: Set<String>] = [:]
        for record in stored where !record.origins.isEmpty {
            restored[record.agent, default: []].formUnion(record.origins)
        }
        grants = restored.merging(added) { $0.union($1) }
        if !added.isEmpty { scheduleSave() }
    }

    /// The grants as the file keeps them.
    private var records: [Record] {
        grants.map { Record(agent: $0.key, origins: $0.value.sorted()) }
    }

    /// Writes a moment after the latest change, on the grants' own queue.
    private func scheduleSave() {
        store.scheduleSave()
    }
}
