import Foundation

/// A coding agent whose own command adds Ode to it: the command's name on
/// PATH, its title in Settings, the words of its add line, and what to know
/// before running it.
struct BrowserAgentCommand: Hashable, Sendable {
    // MARK: - Types

    /// One word of an agent's add line: a literal, or a place the server
    /// name or the helper fills in.
    enum Word: Hashable, Sendable, ExpressibleByStringLiteral {
        case literal(String)
        /// The name Ode registers under.
        case server
        /// The helper's path, quoted for the shell.
        case helper
        /// One JSON object naming the server, the helper and its argument,
        /// quoted for the shell.
        case serverJSON

        init(stringLiteral value: String) {
            self = .literal(value)
        }

        func text(server: String, helper: String) -> String {
            switch self {
            case .literal(let text):
                text
            case .server:
                server
            case .helper:
                "\"\(helper)\""
            case .serverJSON:
                Self.singleQuoted(
                    "{\"name\":\(Self.jsonString(server)),\"command\":\(Self.jsonString(helper)),\"args\":[\"mcp\"]}")
            }
        }

        private static func jsonString(_ text: String) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            guard let data = try? encoder.encode(text) else { return "\"\(text)\"" }
            return String(decoding: data, as: UTF8.self)
        }

        private static func singleQuoted(_ text: String) -> String {
            "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
    }

    // MARK: - Static Variables

    /// The name Ode registers under in every agent.
    static let server = "ode"

    /// User scope: a button in Settings runs in no project folder, and jcode
    /// reads Claude Code's user-level servers. Reasonix reads a project's
    /// `.mcp.json` in the same shape.
    static let claude = Self(
        name: "claude", title: "Claude Code",
        words: ["mcp", "add", "--scope", "user", .server, "--", .helper, "mcp"],
        alsoReaches: ["jcode", "Reasonix"])
    static let codex = Self(name: "codex", title: "Codex", words: ["mcp", "add", .server, "--", .helper, "mcp"])
    /// Pi declares a server's tools to the model only when they are exposed
    /// directly; its default reaches them from scripts alone.
    static let pi = Self(
        name: "pi", title: "Pi", words: ["mcp", "add", .server, "--exposure", "direct", "--", .helper, "mcp"])
    /// OpenClaw saves the server only while its gateway is stopped; its own error says so.
    static let openclaw = Self(
        name: "openclaw", title: "OpenClaw", words: ["mcp", "add", .server, "--command", .helper, "--arg", "mcp"],
        note: String(
            localized: "Stop OpenClaw’s gateway first, or add the server in its Control UI under Settings > MCP."))
    /// Hermes takes the helper's arguments after `--args`, which reads to the end of the line.
    static let hermes = Self(
        name: "hermes", title: "Hermes", words: ["mcp", "add", .server, "--command", .helper, "--args", "mcp"])
    /// Gemini CLI and Qwen Code take the helper positionally; `-s user` keeps
    /// the server out of the current folder's project settings.
    static let gemini = Self(
        name: "gemini", title: "Gemini CLI", words: ["mcp", "add", "-s", "user", .server, .helper, "mcp"])
    /// VS Code's guided setup writes to Copilot CLI's file, so its Copilot
    /// chat reads this registration too.
    static let copilot = Self(
        name: "copilot", title: "GitHub Copilot CLI", words: ["mcp", "add", .server, "--", .helper, "mcp"],
        alsoReaches: ["VS Code"])
    /// OpenCode routes a server's tools through Code Mode unless its entry turns that off.
    static let opencode = Self(
        name: "opencode", title: "OpenCode", words: ["mcp", "add", .server, "--global", "--", .helper, "mcp"],
        note: String(
            localized:
                "Then set codemode to false for ode in ~/.config/opencode/opencode.jsonc, so the model sees Ode’s tools."
        ))
    static let amp = Self(name: "amp", title: "Amp", words: ["mcp", "add", .server, "--", .helper, "mcp"])
    static let code = Self(name: "code", title: "VS Code", words: ["--add-mcp", .serverJSON])
    static let qwen = Self(
        name: "qwen", title: "Qwen Code", words: ["mcp", "add", "-s", "user", .server, .helper, "mcp"])

    static let all: [Self] = [claude, codex, pi, openclaw, hermes, gemini, copilot, opencode, amp, code, qwen]

    // MARK: - Variables

    let name: String
    let title: String
    let words: [Word]
    /// What the person must know before the line runs, when the agent
    /// needs more than the line.
    let note: String?
    /// Other agents that read this agent's registration, so they need none
    /// of their own.
    let alsoReaches: [String]

    // MARK: - Initializers

    init(name: String, title: String, words: [Word], note: String? = nil, alsoReaches: [String] = []) {
        self.name = name
        self.title = title
        self.words = words
        self.note = note
        self.alsoReaches = alsoReaches
    }

    // MARK: - Actions - Registration

    /// The line that adds Ode to the agent, with the helper at `helper`.
    func line(helper: String) -> String {
        ([name] + words.map { $0.text(server: Self.server, helper: helper) }).joined(separator: " ")
    }
}
