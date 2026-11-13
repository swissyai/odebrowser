import Foundation

/// A coding agent that reads its servers from a file it owns: the file, the
/// entry that adds Ode to it with the helper's path filled in, and the link
/// that installs the entry when the agent takes one.
struct BrowserAgentConfigFile: Identifiable, Hashable, Sendable {
    // MARK: - Static Variables

    /// The entry agents with an `mcpServers` object take.
    private static let serversEntry = """
        {
          "mcpServers": {
            "ode": {
              "command": "{helper}",
              "args": ["mcp"]
            }
          }
        }
        """

    /// Characters a link's query value keeps as they are.
    private static let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    static let cursor = Self(
        title: "Cursor", path: "~/.cursor/mcp.json", entry: serversEntry,
        note: String(localized: "Restart Cursor afterwards."),
        installLink: { helper in
            let config = Data("{\"command\":\(jsonString(helper)),\"args\":[\"mcp\"]}".utf8)
            let encoded = config.base64EncodedString()
            return URL(string: "cursor://anysphere.cursor-deeplink/mcp/install?name=ode&config=\(encoded)")
        })
    static let zed = Self(
        title: "Zed", path: "~/.config/zed/settings.json",
        entry: """
            {
              "context_servers": {
                "ode": {
                  "command": "{helper}",
                  "args": ["mcp"],
                  "env": {}
                }
              }
            }
            """)
    static let goose = Self(
        title: "Goose", path: "~/.config/goose/config.yaml",
        entry: """
            extensions:
              ode:
                type: stdio
                name: ode
                enabled: true
                cmd: "{helper}"
                args: ["mcp"]
                envs: {}
                env_keys: []
                timeout: 300
            """,
        note: String(localized: "Restart Goose afterwards. Goose Desktop also takes the link."),
        installLink: { helper in
            guard let command = helper.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
            let query = "cmd=\(command)&arg=mcp&id=ode&name=Ode&description=Browser%20tools%20from%20Ode&timeout=300"
            return URL(string: "goose://extension?\(query)")
        })
    static let claudeDesktop = Self(
        title: "Claude Desktop", path: "~/Library/Application Support/Claude/claude_desktop_config.json",
        entry: serversEntry, note: String(localized: "Quit and reopen Claude Desktop afterwards."))
    static let antigravity = Self(
        title: "Antigravity CLI", path: "~/.gemini/config/mcp_config.json", entry: serversEntry)
    static let mimo = Self(
        title: "MiMo Code", path: "~/.config/mimocode/mimocode.jsonc",
        entry: """
            {
              "mcp": {
                "ode": {
                  "type": "local",
                  "command": ["{helper}", "mcp"],
                  "enabled": true
                }
              }
            }
            """)
    /// The shape most other agents' files take, for one Ode doesn't list.
    static let other = Self(title: "Other agents", path: nil, entry: serversEntry)

    static let all: [Self] = [cursor, zed, goose, claudeDesktop, antigravity, mimo, other]

    // MARK: - Variables

    let title: String
    /// The file, with `~` for the person's home folder, or nil when the
    /// entry stands for no one file.
    let path: String?
    /// The entry, with `{helper}` where the helper's path goes.
    private let entry: String
    /// What to do once the entry is in the file, when the agent needs it.
    let note: String?
    private let installLink: (@Sendable (String) -> URL?)?

    var id: String { title }

    var fileURL: URL? {
        path.map { URL(filePath: NSString(string: $0).expandingTildeInPath) }
    }

    var isFilePresent: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Whether the file's folder exists, which Ode opens but never creates.
    var isFolderPresent: Bool {
        guard let fileURL else { return false }
        var isDirectory: ObjCBool = false
        let folder = fileURL.deletingLastPathComponent().path
        return FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: - Initializers

    init(
        title: String, path: String?, entry: String, note: String? = nil,
        installLink: (@Sendable (String) -> URL?)? = nil
    ) {
        self.title = title
        self.path = path
        self.entry = entry
        self.note = note
        self.installLink = installLink
    }

    // MARK: - Actions - Entries

    /// The entry with the helper at `helper`, escaped as the file's strings are.
    func entry(helper: String) -> String {
        let literal = Self.jsonString(helper)
        return entry.replacingOccurrences(of: "{helper}", with: String(literal.dropFirst().dropLast()))
    }

    /// The agent's own link that installs the entry, when it has one.
    func installLink(helper: String) -> URL? {
        installLink?(helper)
    }

    /// `text` as a JSON string literal, quotes included, which YAML's
    /// double-quoted strings share.
    private static func jsonString(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(text) else { return "\"\(text)\"" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension BrowserAgentConfigFile {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
    }
}
