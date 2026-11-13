import Foundation

// MARK: - Types

/// Execution status, not proof that a website achieved the caller's goal.
enum AgentToolOutcome: String, Codable, CaseIterable, Sendable {
    case completed, refused, unsupported, failed, cancelled, unconfirmed
}

/// Unknown includes submitted input, navigation and scripts that cannot be rolled back.
enum AgentToolEffect: String, Codable, CaseIterable, Sendable {
    case notAttempted, unknown
}

enum AgentToolRefusal: String, Codable, CaseIterable, Sendable {
    case navigationBoundaryUnavailable, screenshotRedactionUnavailable, scriptsDisabled, originApprovalRequired
}

/// The same result in readable content and typed MCP structured content.
struct AgentToolResult: Codable, Equatable, Sendable {
    // MARK: - Static Variables

    static let outputSchema: AgentJSON = .object([
        "type": .string("object"),
        "properties": .object([
            "outcome": .object([
                "type": .string("string"), "enum": .array(AgentToolOutcome.allCases.map { .string($0.rawValue) }),
            ]),
            "effect": .object([
                "type": .string("string"), "enum": .array(AgentToolEffect.allCases.map { .string($0.rawValue) }),
            ]),
            "refusal": .object([
                "type": .string("string"), "enum": .array(AgentToolRefusal.allCases.map { .string($0.rawValue) }),
            ]),
            "data": .object([:]),
            "notes": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
        ]),
        "required": .array([.string("outcome"), .string("effect"), .string("notes")]),
        "additionalProperties": .bool(false),
    ])

    // MARK: - Types

    struct Output: Codable, Equatable, Sendable {
        let outcome: AgentToolOutcome
        let effect: AgentToolEffect
        let refusal: AgentToolRefusal?
        let data: AgentJSON?
        var notes: [String]
    }

    struct Content: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case text, image
        }

        let type: Kind
        let text: String?
        let data: String?
        let mimeType: String?

        static func text(_ text: String) -> Self {
            Self(type: .text, text: text, data: nil, mimeType: nil)
        }
    }

    // MARK: - Variables

    let content: [Content]
    let isError: Bool
    let structuredContent: Output

    // MARK: - Initializers

    init(content: [Content], isError: Bool, output: Output? = nil) {
        self.content = content
        self.isError = isError
        structuredContent =
            output
            ?? Output(
                outcome: isError ? .failed : .completed, effect: .unknown, refusal: nil, data: nil,
                notes: content.compactMap(\.text))
    }

    // MARK: - Actions - Results

    static func error(
        _ message: String, outcome: AgentToolOutcome = .failed, effect: AgentToolEffect = .unknown,
        refusal: AgentToolRefusal? = nil
    ) -> Self {
        Self(
            content: [.text(message)], isError: true,
            output: Output(outcome: outcome, effect: effect, refusal: refusal, data: nil, notes: [message]))
    }
}
