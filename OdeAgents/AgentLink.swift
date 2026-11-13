import Foundation

// What the agent helper and the Ode it ships inside say to each other over
// the agent socket, one JSON object per line. The helper speaks the Model
// Context Protocol with the agent; only tool calls cross to Ode.

// MARK: - Types

/// The agent as it named itself to the helper.
struct AgentClientInfo: Codable, Equatable, Sendable {
    let name: String
    let title: String?
    let version: String?
}

/// Advisory eligibility is not authorization or website success.
struct AgentToolAvailability: Codable, Equatable, Sendable {
    let name: String
    let eligible: Bool
    let refusal: AgentToolRefusal?
}

enum AgentCancellationSupport: String, Codable, Sendable {
    case cooperativeNoRollback
}

enum AgentCapabilityScope: String, Codable, Sendable {
    case engineAndScriptPolicy
}

struct AgentSessionCapabilities: Codable, Equatable, Sendable {
    let session: UUID
    let tab: UUID?
    let allowedSpaces: Int
    let lockedSpaces: Int
    let tools: [AgentToolAvailability]
    let eligibilityScope: AgentCapabilityScope
    let cancellation: AgentCancellationSupport
    let submittedEffectsMayContinue: Bool
    let authorizationRecheckedOnEveryCall: Bool
}

/// What the helper says to Ode.
enum AgentLinkRequest: Codable, Sendable {
    /// The helper connected for the agent `client`, speaking link `version`.
    case attach(version: Int, client: AgentClientInfo?)
    /// The agent called tool `name` with `arguments`, as call `id`.
    case call(id: Int, name: String, arguments: AgentJSON)
    /// Cooperatively stop subsequent work. Already submitted engine effects may continue.
    case cancel(id: Int)
}

/// What Ode says to the helper.
enum AgentLinkResponse: Codable, Sendable {
    /// Ode heard the agent; its tools are `tools`, as the protocol lists
    /// them, which an older helper lists from then on.
    case attached(tools: AgentJSON)
    /// Ode will not talk to this helper, for `reason`.
    case refused(reason: AgentLinkRefusal)
    /// Call `id` answered `result`.
    case result(id: Int, result: AgentToolResult)
}

/// Why Ode refuses a helper.
enum AgentLinkRefusal: String, Codable, Sendable {
    /// The helper is from a build of Ode whose link differs from the one
    /// running, such as the build an update replaced; the agent starts it
    /// again to reach this Ode.
    case staleHelper
    /// The person has agents turned off.
    case agentsOff
}

extension AgentLinkRequest {
    /// The link's revision; a helper and an Ode of different revisions never
    /// talk.
    static let version = 2
    /// The longest line a helper sends Ode. A call past it fails in the
    /// helper, so it never ends the agent's connection.
    static let maximumBytes = 4 << 20
}

extension AgentLinkResponse {
    /// The longest line Ode sends a helper, well within what the helper
    /// reads. An answer past it fails that call.
    static let maximumBytes = 6 << 20
}
