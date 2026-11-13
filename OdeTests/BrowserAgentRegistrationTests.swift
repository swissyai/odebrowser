import XCTest

@testable import Ode

/// The lines Settings runs or copies for coding agents are each agent's own
/// registration syntax. A wrong word is not an error here: the agent saves a
/// server that never starts, or saves nothing.
final class BrowserAgentRegistrationTests: XCTestCase {
    // MARK: - Static Variables

    private static let helper = "/Applications/Ode.app/Contents/Helpers/ode-browser"
    private static let quotedHelper = "\"/Applications/Ode.app/Contents/Helpers/ode-browser\""

    // MARK: - Actions - Lines

    func testClaudeCodeLineRegistersAtUserScope() {
        XCTAssertEqual(
            BrowserAgentCommand.claude.line(helper: Self.helper),
            "claude mcp add --scope user ode -- \(Self.quotedHelper) mcp")
    }

    func testCodexLineIsUnchanged() {
        XCTAssertEqual(
            BrowserAgentCommand.codex.line(helper: Self.helper), "codex mcp add ode -- \(Self.quotedHelper) mcp")
    }

    func testPiLineExposesToolsDirectly() {
        XCTAssertEqual(
            BrowserAgentCommand.pi.line(helper: Self.helper),
            "pi mcp add ode --exposure direct -- \(Self.quotedHelper) mcp")
    }

    func testOpenClawLineIsUnchanged() {
        XCTAssertEqual(
            BrowserAgentCommand.openclaw.line(helper: Self.helper),
            "openclaw mcp add ode --command \(Self.quotedHelper) --arg mcp")
    }

    func testHermesLinePassesTheArgumentAfterArgs() {
        XCTAssertEqual(
            BrowserAgentCommand.hermes.line(helper: Self.helper),
            "hermes mcp add ode --command \(Self.quotedHelper) --args mcp")
    }

    func testGeminiLineIsPositionalAtUserScope() {
        XCTAssertEqual(
            BrowserAgentCommand.gemini.line(helper: Self.helper), "gemini mcp add -s user ode \(Self.quotedHelper) mcp")
    }

    func testCopilotLine() {
        XCTAssertEqual(
            BrowserAgentCommand.copilot.line(helper: Self.helper), "copilot mcp add ode -- \(Self.quotedHelper) mcp")
    }

    func testOpenCodeLineIsGlobal() {
        XCTAssertEqual(
            BrowserAgentCommand.opencode.line(helper: Self.helper),
            "opencode mcp add ode --global -- \(Self.quotedHelper) mcp")
    }

    func testAmpLine() {
        XCTAssertEqual(BrowserAgentCommand.amp.line(helper: Self.helper), "amp mcp add ode -- \(Self.quotedHelper) mcp")
    }

    func testVSCodeLinePassesTheServerAsJSON() {
        XCTAssertEqual(
            BrowserAgentCommand.code.line(helper: Self.helper),
            "code --add-mcp '{\"name\":\"ode\",\"command\":\"\(Self.helper)\",\"args\":[\"mcp\"]}'")
    }

    func testQwenLineIsPositionalAtUserScope() {
        XCTAssertEqual(
            BrowserAgentCommand.qwen.line(helper: Self.helper), "qwen mcp add -s user ode \(Self.quotedHelper) mcp")
    }

    func testVSCodeLineKeepsAPathWithSpacesAndQuotesInsideTheJSON() {
        let helper = "/Users/person/My Apps/Ode's Copy.app/Contents/Helpers/ode-browser"
        XCTAssertEqual(
            BrowserAgentCommand.code.line(helper: helper),
            "code --add-mcp '{\"name\":\"ode\",\"command\":\"/Users/person/My Apps/Ode'\\''s Copy.app/Contents/Helpers/ode-browser\",\"args\":[\"mcp\"]}'"
        )
    }

    // MARK: - Actions - Reach

    func testClaudeCodeRegistrationAlsoReachesJcodeAndReasonix() {
        XCTAssertEqual(BrowserAgentCommand.claude.alsoReaches, ["jcode", "Reasonix"])
    }

    func testCopilotRegistrationAlsoReachesVSCode() {
        XCTAssertEqual(BrowserAgentCommand.copilot.alsoReaches, ["VS Code"])
    }

    func testNoOtherRegistrationClaimsToReachAnotherAgent() {
        for command in BrowserAgentCommand.all where command != .claude && command != .copilot {
            XCTAssertTrue(command.alsoReaches.isEmpty, command.title)
        }
    }

    // MARK: - Actions - Set

    func testEveryLineRunsItsOwnCommandAndCommandsAreDistinct() {
        for command in BrowserAgentCommand.all {
            XCTAssertTrue(command.line(helper: Self.helper).hasPrefix(command.name + " "), command.title)
        }
        XCTAssertEqual(Set(BrowserAgentCommand.all.map(\.name)).count, BrowserAgentCommand.all.count)
    }

    // MARK: - Actions - Config files

    func testCursorEntryAndFile() {
        XCTAssertEqual(BrowserAgentConfigFile.cursor.path, "~/.cursor/mcp.json")
        XCTAssertEqual(
            BrowserAgentConfigFile.cursor.entry(helper: Self.helper),
            """
            {
              "mcpServers": {
                "ode": {
                  "command": "\(Self.helper)",
                  "args": ["mcp"]
                }
              }
            }
            """)
    }

    func testZedEntryAndFile() {
        XCTAssertEqual(BrowserAgentConfigFile.zed.path, "~/.config/zed/settings.json")
        XCTAssertEqual(
            BrowserAgentConfigFile.zed.entry(helper: Self.helper),
            """
            {
              "context_servers": {
                "ode": {
                  "command": "\(Self.helper)",
                  "args": ["mcp"],
                  "env": {}
                }
              }
            }
            """)
    }

    func testGooseEntryAndFile() {
        XCTAssertEqual(BrowserAgentConfigFile.goose.path, "~/.config/goose/config.yaml")
        XCTAssertEqual(
            BrowserAgentConfigFile.goose.entry(helper: Self.helper),
            """
            extensions:
              ode:
                type: stdio
                name: ode
                enabled: true
                cmd: "\(Self.helper)"
                args: ["mcp"]
                envs: {}
                env_keys: []
                timeout: 300
            """)
    }

    func testClaudeDesktopEntryAndFile() {
        XCTAssertEqual(
            BrowserAgentConfigFile.claudeDesktop.path,
            "~/Library/Application Support/Claude/claude_desktop_config.json")
        XCTAssertEqual(
            BrowserAgentConfigFile.claudeDesktop.entry(helper: Self.helper),
            BrowserAgentConfigFile.cursor.entry(helper: Self.helper))
    }

    func testAntigravityEntryAndFile() {
        XCTAssertEqual(BrowserAgentConfigFile.antigravity.path, "~/.gemini/config/mcp_config.json")
        XCTAssertEqual(
            BrowserAgentConfigFile.antigravity.entry(helper: Self.helper),
            BrowserAgentConfigFile.cursor.entry(helper: Self.helper))
    }

    func testMiMoCodeEntryAndFile() {
        XCTAssertEqual(BrowserAgentConfigFile.mimo.path, "~/.config/mimocode/mimocode.jsonc")
        XCTAssertEqual(
            BrowserAgentConfigFile.mimo.entry(helper: Self.helper),
            """
            {
              "mcp": {
                "ode": {
                  "type": "local",
                  "command": ["\(Self.helper)", "mcp"],
                  "enabled": true
                }
              }
            }
            """)
    }

    func testOtherAgentsEntryStandsForNoFile() {
        XCTAssertNil(BrowserAgentConfigFile.other.path)
        XCTAssertNil(BrowserAgentConfigFile.other.fileURL)
        XCTAssertFalse(BrowserAgentConfigFile.other.isFolderPresent)
        XCTAssertEqual(
            BrowserAgentConfigFile.other.entry(helper: Self.helper),
            BrowserAgentConfigFile.cursor.entry(helper: Self.helper))
    }

    func testEntriesEscapeTheHelperPathAsAString() {
        let helper = "/Users/person/My \"Apps\"/Ode.app/Contents/Helpers/ode-browser"
        XCTAssertTrue(
            BrowserAgentConfigFile.cursor.entry(helper: helper).contains(
                "\"command\": \"/Users/person/My \\\"Apps\\\"/Ode.app/Contents/Helpers/ode-browser\""))
        XCTAssertTrue(
            BrowserAgentConfigFile.goose.entry(helper: helper).contains(
                "cmd: \"/Users/person/My \\\"Apps\\\"/Ode.app/Contents/Helpers/ode-browser\""))
    }

    func testFilePathsExpandToTheHomeFolder() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for file in BrowserAgentConfigFile.all where file.path != nil {
            let url = try XCTUnwrap(file.fileURL, file.title)
            XCTAssertTrue(url.path.hasPrefix(home + "/"), file.title)
            XCTAssertFalse(url.path.contains("~"), file.title)
        }
    }

    // MARK: - Actions - Install links

    func testCursorInstallLinkCarriesTheEntryAsBase64() {
        XCTAssertEqual(
            BrowserAgentConfigFile.cursor.installLink(helper: Self.helper)?.absoluteString,
            "cursor://anysphere.cursor-deeplink/mcp/install?name=ode&config="
                + "eyJjb21tYW5kIjoiL0FwcGxpY2F0aW9ucy9PZGUuYXBwL0NvbnRlbnRzL0hlbHBlcnMvb2RlLWJyb3dzZXIi"
                + "LCJhcmdzIjpbIm1jcCJdfQ==")
    }

    func testGooseInstallLinkEncodesTheHelperAndArgument() {
        XCTAssertEqual(
            BrowserAgentConfigFile.goose.installLink(helper: Self.helper)?.absoluteString,
            "goose://extension?cmd=%2FApplications%2FOde.app%2FContents%2FHelpers%2Fode-browser&arg=mcp&id=ode"
                + "&name=Ode&description=Browser%20tools%20from%20Ode&timeout=300")
    }

    func testOnlyCursorAndGooseOfferInstallLinks() {
        for file in BrowserAgentConfigFile.all where file != .cursor && file != .goose {
            XCTAssertNil(file.installLink(helper: Self.helper), file.title)
        }
    }
}
