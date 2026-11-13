import Foundation

/// One tool call an agent made: the service that answers it, the agent's
/// connection and core session, and the arguments it passed, which each tool
/// reads as its own typed values.
@MainActor
final class BrowserAgentCall {
    // MARK: - Variables

    unowned let agents: BrowserMacAgents
    let link: BrowserMacAgents.Link
    let sessionID: UUID
    let arguments: AgentJSON

    // MARK: - Initializers

    init(agents: BrowserMacAgents, link: BrowserMacAgents.Link, sessionID: UUID, arguments: AgentJSON) {
        self.agents = agents
        self.link = link
        self.sessionID = sessionID
        self.arguments = arguments
    }

    // MARK: - Actions - Driving

    /// The first successful claim starts driving before any page input or
    /// load, including the session's first call on an existing tab.
    func drive(_ tabID: UUID) {
        guard link.drivenTabs.insert(tabID).inserted else { return }
        BrowserAgentOriginGate.sessions.drive(tabID, by: link.gate)
    }

    // MARK: - Actions - Arguments

    /// The arguments as `Arguments`, or the failure that names what is wrong.
    func arguments<Arguments: Decodable>(_: Arguments.Type) throws(BrowserAgentFailure) -> Arguments {
        do {
            return try arguments.decoded(as: Arguments.self)
        } catch let error as DecodingError {
            throw .invalidArguments(Self.explanation(of: error))
        } catch {
            throw .invalidArguments(error.localizedDescription)
        }
    }

    private static func explanation(of error: DecodingError) -> String {
        func name(_ path: [any CodingKey]) -> String { path.map(\.stringValue).joined(separator: ".") }
        switch error {
        case .keyNotFound(let key, let context): return "\(name(context.codingPath + [key])) is missing."
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(name(context.codingPath)) is not valid."
        @unknown default: return "they could not be read."
        }
    }
}

extension AgentToolResult {
    /// Data and notes are present in structured content as well as fallback
    /// text, so clients that prefer structured results do not lose a warning.
    static func data(_ value: some Encodable, note: String? = nil) -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let text = (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return Self(
            content: [.text(note.map { "\($0)\n\(text)" } ?? text)], isError: false,
            output: Output(
                outcome: .completed, effect: .unknown, refusal: nil, data: .encoded(value),
                notes: note.map { [$0] } ?? []))
    }

    /// A message the model reads.
    static func message(_ text: String) -> Self {
        Self(content: [.text(text)], isError: false)
    }

    /// The result with `note` after what it says.
    func noting(_ note: String) -> Self {
        var content = content
        if let last = content.lastIndex(where: { $0.text != nil }), let text = content[last].text {
            content[last] = .text("\(text)\n\n\(note)")
        } else {
            content.append(.text(note))
        }
        var output = structuredContent
        output.notes.append(note)
        return Self(content: content, isError: isError, output: output)
    }
}
