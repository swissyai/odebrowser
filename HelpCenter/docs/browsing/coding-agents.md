---
title: Let coding agents use Ode
description: Let coding agents on your Mac, such as Claude Code and Codex, read and act on tabs in the Spaces you choose, and stay in control of what they do.
slug: /coding-agents
keywords: [agents, AI, MCP, Model Context Protocol, coding agents, Claude Code, Codex, Pi, OpenClaw, Hermes, Gemini CLI, GitHub Copilot, OpenCode, Amp, VS Code, Qwen Code, Cursor, Zed, Goose, Claude Desktop, Antigravity, MiMo Code, automation]
---

# Let coding agents use Ode

Coding agents you run on your Mac, such as Claude Code, Codex, Pi, Gemini CLI or Cursor, can use Ode as their browser: open and read tabs, click and type, and read a page's console and network requests. They work in the Spaces you choose, with the sites you're already signed in to there.

Agents are off until you turn them on. They run on your own plan or machine; Ode runs no model and sends nothing to any AI service.

Page tools currently require a WebKit-only build. In the standard Chromium app, agents can identify themselves and list allowed Spaces and tabs, but page operations return `unsupported` until the engine can check navigation before sending a request. Agent screenshots are unavailable on every engine.

## Let a coding agent use Ode {#turn-on-agents}

1. Choose Ode > Settings, click Agents and turn on Allow agents to use Ode.
2. Under Spaces, turn on each Space agents may use. Turning on a Space of a [Sub-Space](../spaces/sub-spaces.md) group turns on the whole group.
3. Under Connect an Agent, click Connect beside your agent, or Copy Setup and paste it into the agent.

Agents run on your own plan. Ode runs no model and sends nothing to an AI service.

Ode must be open while an agent works. Before an agent opens a window, Ode asks you; you can let it open windows without asking until it disconnects, except private windows, which Ode always asks about. If Ode isn't in your Applications folder, Settings asks you to move it there first.

## Connect with one click {#connect-agents}

Under Connect an Agent, Ode lists the agents whose own command adds a server: Claude Code, Codex, Pi, OpenClaw, Hermes, Gemini CLI, GitHub Copilot CLI, OpenCode, Amp, VS Code and Qwen Code. Connect appears beside each one whose command is on your Mac; it runs that agent's line through your login shell and shows what the agent said. Copy Setup copies the same line to paste into a terminal.

Every line names the helper inside your copy of Ode. For Ode in Applications that is `/Applications/Ode.app/Contents/Helpers/ode-browser`, written `<helper>` here:

| Agent | What Connect runs |
| --- | --- |
| Claude Code | `claude mcp add --scope user ode -- "<helper>" mcp` |
| Codex | `codex mcp add ode -- "<helper>" mcp` |
| Pi | `pi mcp add ode --exposure direct -- "<helper>" mcp` |
| OpenClaw | `openclaw mcp add ode --command "<helper>" --arg mcp` |
| Hermes | `hermes mcp add ode --command "<helper>" --args mcp` |
| Gemini CLI | `gemini mcp add -s user ode "<helper>" mcp` |
| GitHub Copilot CLI | `copilot mcp add ode -- "<helper>" mcp` |
| OpenCode | `opencode mcp add ode --global -- "<helper>" mcp` |
| Amp | `amp mcp add ode -- "<helper>" mcp` |
| VS Code | `code --add-mcp '{"name":"ode","command":"<helper>","args":["mcp"]}'` |
| Qwen Code | `qwen mcp add -s user ode "<helper>" mcp` |

A few agents need one more thing, and the pane says so under their row:

- Pi hides a server's tools from the model unless they are exposed directly, so Ode's line passes `--exposure direct`.
- OpenClaw saves the server only while its gateway is stopped. Stop it before choosing Connect, or add the server in OpenClaw's Control UI under Settings > MCP.
- OpenCode routes tools through its Code Mode by default. After connecting, set `"codemode": false` on the `ode` entry in `~/.config/opencode/opencode.jsonc` so the model sees Ode's tools.
- Claude Code, Gemini CLI and Qwen Code register at user scope, with `--scope user` or `-s user`, so the server isn't tied to the folder the command ran in. Gemini CLI and Qwen Code also take the helper positionally.

## One connection, several agents {#also-reaches}

Some agents read another agent's registration, so they need none of their own, and the pane says "Also reaches" under that agent's row. jcode reads Claude Code's user-level servers, and Reasonix reads a project's `.mcp.json` in the same shape, so connecting Claude Code reaches both. VS Code's guided MCP setup writes to GitHub Copilot CLI's `~/.copilot/mcp-config.json`, so connecting Copilot CLI also reaches Copilot in VS Code.

## Add to a config file {#config-file-agents}

Cursor, Zed, Goose, Claude Desktop, Antigravity CLI and MiMo Code read their servers from a file they own. Under Add to a Config File, choose the agent to see the entry with the helper's path filled in. Copy copies the entry; Open Config Folder shows the file's folder in Finder when the folder exists. Ode never edits these files itself. Cursor and Goose also take an install link: Install in Cursor and Install in Goose open the agent with the entry ready to approve.

The files, for Ode in Applications:

Cursor, `~/.cursor/mcp.json`, then restart Cursor:

```json
{ "mcpServers": { "ode": { "command": "/Applications/Ode.app/Contents/Helpers/ode-browser", "args": ["mcp"] } } }
```

Zed, `~/.config/zed/settings.json`:

```json
{ "context_servers": { "ode": { "command": "/Applications/Ode.app/Contents/Helpers/ode-browser", "args": ["mcp"], "env": {} } } }
```

Goose, `~/.config/goose/config.yaml`, then restart Goose:

```yaml
extensions:
  ode:
    type: stdio
    name: ode
    enabled: true
    cmd: "/Applications/Ode.app/Contents/Helpers/ode-browser"
    args: ["mcp"]
    envs: {}
    env_keys: []
    timeout: 300
```

Claude Desktop, `~/Library/Application Support/Claude/claude_desktop_config.json`, then quit and reopen Claude Desktop:

```json
{ "mcpServers": { "ode": { "command": "/Applications/Ode.app/Contents/Helpers/ode-browser", "args": ["mcp"] } } }
```

Antigravity CLI, `~/.gemini/config/mcp_config.json`:

```json
{ "mcpServers": { "ode": { "command": "/Applications/Ode.app/Contents/Helpers/ode-browser", "args": ["mcp"] } } }
```

MiMo Code, `~/.config/mimocode/mimocode.jsonc`:

```json
{ "mcp": { "ode": { "type": "local", "command": ["/Applications/Ode.app/Contents/Helpers/ode-browser", "mcp"], "enabled": true } } }
```

For an agent that isn't listed, choose Other agents for the `mcpServers` entry most agents take.

To start Ode without bringing it to the front, a tool can run `open -g --env ODE_BACKGROUND_LAUNCH=1 -a Ode`. Ode opens your windows behind the app you're using, and comes forward only to ask you something, such as about an agent it hasn't met.

## Allow an agent

The first time an agent uses Ode, Ode asks whether to allow it. The question names the program macOS verified by its signature, not the name the agent gives itself. Ode remembers your answer and lists the agent under Allowed agents. When the program is a general interpreter, such as node or python, allowing it covers any program it runs under the same agent name.

## What agents can and can't reach {#agent-spaces}

Agents reach only the Spaces you turn on, and never a private window or a locked Space's tabs. An agent can open a new private window for you, but never reads or acts in one. They search and delete history only in the Spaces you turn on, never private history. They can't read saved passwords, read or type into password, one-time code or card fields, or save a download without you. Ode asks you before an agent opens a site you haven't allowed for it.

A tab an agent is using shows the agent's badge and an outline in its color, and a bar at the top names the agent. A pointer in the agent's color shows where it clicks, hovers, fills and scrolls.

Before an agent deletes history, Ode asks you, naming the agent, the address and the Space.

## Stop an agent working in a tab {#stop-agent}

1. Click Stop in the bar above the tab the agent is using.
2. To end its connection, choose Ode > Settings, click Agents, then Disconnect. Forget makes Ode ask again next time.

To stop every agent at once, choose Ode > Stop All Agents, or click Stop All Agents in Settings > Agents. Every agent disconnects and stays out of the tabs it used until Ode quits.

## See what agents did {#agent-activity}

1. Choose Ode > Settings, then click Agents.
2. Look under Activity, newest first. Click Clear to empty it.

## Why Ode asks before an agent's download {#agent-download}

A download that starts in a tab an agent is using waits for you. Ode names the agent in its question. Allow it, or decline to cancel it.

Turn on Let agents run scripts in pages only if you need it. A script runs with the page's own access, so it can read and change anything the page holds, including password and card fields and what you filled in them.

Any program running as you on your Mac can run an agent you allowed. Allow only agents you trust, and turn agents off when you don't need them.

## For agent authors

Ode includes a Model Context Protocol server as a helper inside the app, `Contents/Helpers/ode-browser`, which an agent runs over its standard input and output:

```text
/Applications/Ode.app/Contents/Helpers/ode-browser mcp
```

It speaks protocol version 2026-07-28 and the earlier versions that open with `initialize`. Call `identify` first with your name and brand color as `#RRGGBB`, so the person sees which tabs you use. Then use `list_spaces` and `list_tabs`, and read pages with `take_snapshot`, whose element `uid`s `click`, `hover`, `fill` and `scroll` take, or with `read_page` as Markdown. The other tools are `open_tab`, `navigate`, `show_tab`, `close_tab`, `screenshot`, `type_text`, `press_key`, `wait_for`, `list_console_messages`, `list_network_requests`, `get_network_request`, `evaluate_script`, `read_page_text`, `handle_dialog`, `search_history`, `delete_history`, `list_search_providers`, `open_window`, `open_blank_window`, `open_quick_window` and `open_private_window`.

`read_page_text` answers a page's readable text as Markdown, without any form field's value. `handle_dialog` answers a page's alert, confirm or prompt, but never a question about leaving the page. `wait_for` also takes `url`, to wait until the tab's address contains it. Tools that open a window wait while Ode asks the person.

Ode asks the person before you open a site. When `open_tab` or `navigate` names an address whose origin, its scheme, host and port, the person hasn't allowed for your session, nothing loads and the call fails with an error that starts with `gate_required` and names the origin. The bar of the tab, or for `open_tab` the bar of the tab you used last, shows that you want to open it, with Allow and Stop. Wait for the person: once they choose Allow, make the same call again; Stop keeps you out of the tab. For a recognized agent, allowed origins remain until the person removes them in Settings; an unidentified session keeps them only until it ends. Merely using an existing tab never grants its origin.

The same check covers every page navigation in a tab you drive, from the first successful claim until you disconnect or the person stops you in that tab. When a link you click, a form you submit, a redirect after it, a script or a window the page opens would leave for a site the person hasn't allowed and that isn't the page's own, Ode holds it, the tab's bar asks the person, and your next answer about the tab ends with a note that starts with `gate_required`. Once they allow it, repeat what led there. A window without an address doesn't open while you drive the tab. On WebKit, a window that does open keeps its opener's approval boundary for redirects and later navigations, with questions shown in the opener's bar. Idle time does not release the tab: delayed scripts and the person's clicks remain checked alike. To browse without the agent's site restrictions, the person can click Stop in the tab's agent bar or choose Stop Agent in This Tab from its status menu; disconnecting the agent also releases its tabs. This is a top-level navigation check, not a network firewall: embedded frames and other page resources still load normally.

`take_snapshot` starts its outline with a line giving the page's title, address, element count and size, so you can read less next time. Each level is indented by one space, and links on the page's own site show their path rather than the full address. A container named by its text, such as a list item, shows that name only when none of what it holds is listed. The outline covers the whole page, whether or not it is scrolled into view, and frames from the page's own site as part of it. A frame from another site is listed with its address and `[other site]`; to read it, open that address with `open_tab`. `skeleton` lists only headings and landmarks, each with how many elements it holds. `uid` reads one element and what it holds, or a heading and its section up to the next heading of its level. `depth` keeps only the outline's levels down to that number, with 0 the outermost. `filter` keeps only elements whose role, name or text contains it, ignoring case, along with their ancestors. `find` does the same and says how many elements matched. `max_chars` caps the outline's size: 60000 characters by default, from 2000 to 1000000. An outline cut at `max_chars` ends with a note naming the last element it listed; call `take_snapshot` again with that uid as `after` to read on from there.

Ode keeps a separate change baseline for each agent session and document. Every successful ordinary `take_snapshot`, even a filtered, scoped, skeleton or capped read, establishes the whole page's current outline as that baseline. `read_page` and screenshots do not change it. `take_snapshot` with `changes` compares that whole-page state: lines added under the element they went into, changed element lines, and removed lines, or "Nothing changed". It ignores `depth`, `filter`, `find`, `uid`, `after` and `skeleton`, but still respects `max_chars`. With no earlier baseline, or when the diff exceeds both 2000 characters and half the current outline, it returns the whole outline. These are line-content changes, not a replay of DOM events; reordering otherwise identical lines alone is not reported. Navigation to a new document starts without a baseline.

A complete change read advances the baseline; a cut change read keeps it. Repeat a cut change read with a larger `max_chars`, rather than `after`, to receive all changes. Invalid uid reads do not advance it. `click`, `fill` and `press_key` take `report`, which waits for the page to settle and then adds changes in up to 2000 characters, or only their counts when more changed. A complete report advances the baseline; a count-only report, or a report without an earlier baseline, does not.

`read_page` reads the page's main content as Markdown, which is usually several times smaller than the outline. When the page links its own Markdown on its own site, as many documentation sites do with `<link rel="alternate" type="text/markdown">`, Ode reads that in the tab's session; otherwise it finds the main content in the page, or with `full_page` converts the whole page. Hidden text and form fields are never part of it. Nothing in it has a uid, so to act on the page, use `take_snapshot` with `find` or `filter`. `max_chars` caps it at 60000 characters by default, and `offset` reads on past a cut.

`screenshot` is listed for protocol compatibility but currently returns `unsupported` before any page lookup or capture, for every viewport, full-page, element and scale request. No image bytes are returned. Neither published engine can guarantee protected-field redaction inside every cross-origin frame and closed shadow root, including one attached to an ordinary HTML element. DOM inspection followed by capture is not an atomic privacy boundary. Use `take_snapshot` or `read_page` instead. Restoring agent screenshots requires trusted renderer-backed redaction; ordinary browser and test-harness captures are unaffected.

Ode won't type while the page's focus is in a frame from another site or inside a component's closed shadow root, because it can't see which field would take the text. A character pressed with `press_key` counts as typing, and the outline shows `[password]` or `[protected]` instead of the value of a field only the person fills.

Network requests never show bodies, and cookies, tokens and other credentials in their headers and addresses are hidden.

When a page runs on WebKit, input reaches it as script events, which some pages ignore, and its network requests show their address, type and timing without their method, status or headers. The published Chromium engine has no pre-request navigation approval hook. Agent page operations therefore return `unsupported` on Chromium rather than send a request and stop it afterwards. Agent page operations require a WebKit-only engine roster. When Chromium or another engine is registered, they return `unsupported`, even for an already loaded WebKit tab: site rules, restored history and link routing must not select an engine before the host can intervene. `list_spaces`, `list_tabs` and agent identification remain available. A WebKit-only build supports page operations normally. Restoring Chromium agent support requires an engine-level pre-request approval hook.

## Launchers and other tools

Launchers and other local tools use the same helper, approval and Spaces as coding agents.

- `list_spaces` says which Space is active and includes each unlocked Space's icon. `list_tabs` says whether each tab is pinned or saved and which folders hold it.
- `show_tab` shows the tab itself, opening a normal window over its Space only when none is open. `close_tab` closes only open tabs.
- `search_history` searches the history of the allowed, unlocked Spaces, newest first. Every word of `query` must appear in the title or address, `domain` matches a host and its subdomains, and `limit` takes 1 through 1000, 25 by default.
- `delete_history` removes every visit to one `url`, without its fragment, from one allowed, unlocked `space`, once the person agrees. An address with no visits removes nothing and asks nothing.
- `list_search_providers` lists the enabled search providers and a Space's default.
- `open_window`, `open_blank_window` and `open_quick_window` open a window over an allowed, unlocked Space, at an `http` or `https` address where they take one. `open_private_window` answers only with the window's ID; an address opens only in a new Private Window.
