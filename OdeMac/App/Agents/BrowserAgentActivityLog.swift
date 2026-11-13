import Foundation
import Observation

/// What agents did in Ode, call by call: when, which agent in which colour,
/// the tool, the tab it named, what it asked without the secrets it passed,
/// and how the call went. The log keeps the newest entries for the app's run
/// and in its own Application Support directory, so it survives a relaunch,
/// until the person clears it.
@Observable
@MainActor
final class BrowserAgentActivityLog {
    // MARK: - Static Variables

    static let shared = BrowserAgentActivityLog(file: storageFile(for: .current))
    /// How many entries the log keeps; older ones go first.
    static let maximumCount = 2000
    static let fileName = "activity.json"

    /// The argument keys whose values may be secrets, which summaries never
    /// show, at any depth.
    private static let secretKeys: Set<String> = ["value", "text", "password", "password_value", "cookie"]
    private static let placeholder = "•••"
    private static let maximumSummaryLength = 200
    private static let maximumStringLength = 60
    /// How long the log waits after a change before writing, so a burst of
    /// calls writes once.
    private static let saveDelay: Duration = .seconds(2)

    // MARK: - Types

    /// One tool call an agent made.
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        /// How a call went: done, or the error text the agent read.
        enum Outcome: Codable, Equatable, Sendable {
            case ok
            case failed(String)
        }

        let id: UUID
        let time: Date
        /// The agent's connection in the core, or nil when the call came
        /// before the person allowed it.
        let sessionID: UUID?
        let agentName: String
        let agentColor: BrandColor?
        let tool: String
        /// The tab the call's arguments named, when they named one.
        let tabID: UUID?
        let tabTitle: String?
        let tabURL: String?
        let summary: String
        let outcome: Outcome

        init(
            id: UUID = UUID(), time: Date = .now, sessionID: UUID?, agentName: String, agentColor: BrandColor?,
            tool: String, tabID: UUID?, tabTitle: String?, tabURL: String?, summary: String, outcome: Outcome
        ) {
            self.id = id
            self.time = time
            self.sessionID = sessionID
            self.agentName = agentName
            self.agentColor = agentColor
            self.tool = tool
            self.tabID = tabID
            self.tabTitle = tabTitle
            self.tabURL = tabURL
            self.summary = summary
            self.outcome = outcome
        }
    }

    // MARK: - Variables

    /// The entries, oldest first.
    private(set) var entries: [Entry] = []
    /// Whether Show Activity asked Settings › Agents to bring the activity
    /// into view, which the pane does once and then sets back.
    var isRevealRequested = false

    /// The file the log is kept in, or none when this launch keeps it in
    /// memory.
    @ObservationIgnored private let store: BrowserAgentFileStore<[Entry]>

    // MARK: - Initializers

    init(file: URL?) {
        store = BrowserAgentFileStore(
            file: file, name: "Agent activity", queueLabel: "activity", saveDelay: Self.saveDelay)
        store.load(
            restore: { [weak self] stored in self?.restore(stored ?? []) },
            snapshot: { [weak self] in self?.entries })
    }

    /// The log's file for `environment`: the installed app's, or the one a
    /// persistent review launch keeps apart from it. Nil keeps the log in
    /// memory.
    static func storageFile(for environment: BrowserLaunchEnvironment) -> URL? {
        BrowserAgentFileStore<[Entry]>.file(named: fileName, for: environment)
    }

    // MARK: - Actions - Entries

    /// Adds `entry` as the newest, keeping only the newest `maximumCount`.
    func append(_ entry: Entry) {
        entries.append(entry)
        trim()
        scheduleSave()
    }

    /// The entries of the agent connection `sessionID`, oldest first.
    func entries(for sessionID: UUID) -> [Entry] {
        entries.filter { $0.sessionID == sessionID }
    }

    /// The entries of calls that named tab `tabID`, oldest first.
    func entries(forTab tabID: UUID) -> [Entry] {
        entries.filter { $0.tabID == tabID }
    }

    func clear() {
        entries.removeAll()
        scheduleSave()
    }

    /// A one-line account of `arguments`, leaving out the keys in `omitted`
    /// at the top level and hiding every value that may be a secret.
    static func summary(of arguments: AgentJSON, omitting omitted: Set<String> = []) -> String {
        let text: String
        if case .object(let object) = arguments {
            text = object.keys.sorted().filter { !omitted.contains($0) }.map { key in
                "\(key): \(secretKeys.contains(key) ? placeholder : describe(object[key] ?? .null))"
            }.joined(separator: ", ")
        } else {
            text = describe(arguments)
        }
        return truncated(text, to: maximumSummaryLength)
    }

    private static func describe(_ value: AgentJSON) -> String {
        switch value {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            return value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .string(let value):
            let line = value.components(separatedBy: .newlines).joined(separator: " ")
            return "\"\(truncated(line, to: maximumStringLength))\""
        case .array(let values): return "[\(values.map(describe).joined(separator: ", "))]"
        case .object(let object):
            let pairs = object.keys.sorted().map { key in
                "\(key): \(secretKeys.contains(key) ? placeholder : describe(object[key] ?? .null))"
            }
            return "{\(pairs.joined(separator: ", "))}"
        }
    }

    private static func truncated(_ text: String, to length: Int) -> String {
        text.count > length ? "\(text.prefix(length - 1))…" : text
    }

    private func trim() {
        if entries.count > Self.maximumCount { entries.removeFirst(entries.count - Self.maximumCount) }
    }

    // MARK: - Actions - Storage

    /// Puts the stored entries before those added while they were read.
    private func restore(_ stored: [Entry]) {
        let added = entries
        entries = stored + added
        trim()
        if !added.isEmpty { scheduleSave() }
    }

    /// Writes a moment after the latest change, on the log's own queue, so a
    /// tool call never waits for the disk.
    private func scheduleSave() {
        store.scheduleSave()
    }
}
