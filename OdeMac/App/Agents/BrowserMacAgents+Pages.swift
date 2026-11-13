import AppKit

/// What an agent may do with the page of a tab it uses: read it as an
/// outline, capture it, click, hover, fill, type, press keys and scroll, wait
/// for it, read its console and network activity, and, when the person lets
/// it, run scripts in the page's own world. A tab's page loads for the agent
/// without a window showing it, and keeps rendering while the agent uses it.
/// Calls on one tab run one at a time.
extension BrowserMacAgents {
    // MARK: - Types

    /// The claimed tab and exact resident engine page selected before any await.
    /// Subsequent work validates this receipt without claiming the tab again.
    private struct PageAccess {
        let tabID: UUID
        let page: BrowserPage
        let engine: EnginePage
    }

    private struct ElementReference: Decodable {
        let tab: UUID
        let uid: String
    }

    private struct Reading: Decodable {
        enum CodingKeys: String, CodingKey {
            case tab, depth, filter, find, uid, after, skeleton, changes
            case maxChars = "max_chars"
        }

        let tab: UUID
        let depth: Double?
        let filter: String?
        let find: String?
        let maxChars: Double?
        let uid: String?
        let after: String?
        let skeleton: Bool?
        let changes: Bool?
    }

    private struct MarkdownReading: Decodable {
        enum CodingKeys: String, CodingKey {
            case tab, offset
            case fullPage = "full_page"
            case maxChars = "max_chars"
        }

        let tab: UUID
        let fullPage: Bool?
        let maxChars: Double?
        let offset: Double?
    }

    private struct Click: Decodable {
        enum Button: String, Decodable {
            case left, right, middle

            var pointer: PointerButton {
                switch self {
                case .left: .primary
                case .right: .secondary
                case .middle: .middle
                }
            }
        }

        let tab: UUID
        let uid: String
        let double: Bool?
        let button: Button?
        let report: Bool?
    }

    private struct Fill: Decodable {
        let tab: UUID
        let uid: String
        let value: String
        let report: Bool?
    }

    private struct Typing: Decodable {
        let tab: UUID
        let text: String
    }

    private struct KeyPress: Decodable {
        enum Modifier: String, Decodable {
            case shift = "Shift"
            case control = "Control"
            case option = "Option"
            case command = "Command"

            var keys: KeyModifiers {
                switch self {
                case .shift: .shift
                case .control: .control
                case .option: .option
                case .command: .command
                }
            }
        }

        let tab: UUID
        let key: String
        let modifiers: [Modifier]?
        let report: Bool?
    }

    private struct Scrolling: Decodable {
        let tab: UUID
        let uid: String?
        let dx: Double?
        let dy: Double?
    }

    private struct Waiting: Decodable {
        enum CodingKeys: String, CodingKey {
            case tab, text, url
            case timeout = "timeout_ms"
        }

        let tab: UUID
        let text: String?
        let url: String?
        let timeout: Double?
    }

    private struct TextReading: Decodable {
        enum CodingKeys: String, CodingKey {
            case tab
            case limit = "max_chars"
        }

        let tab: UUID
        let limit: Int?
    }

    private struct PageText: Decodable {
        let url: String
        let title: String
        let text: String
        let truncated: Bool
    }

    private struct DialogAnswer: Decodable {
        let tab: UUID
        let accept: Bool
        let text: String?
    }

    private struct Since: Decodable {
        let tab: UUID
        let since: Int64?
    }

    private struct RequestReference: Decodable {
        let tab: UUID
        let id: Int64
    }

    private struct Script: Decodable {
        let tab: UUID
        let function: String
    }

    /// Where the element a uid names is in the viewport, in CSS pixels.
    private struct Located: Decodable {
        let x: Double
        let y: Double
        let left: Double
        let top: Double
        let width: Double
        let height: Double
        let tag: String
    }

    /// What an agent's text would go into, as the page reports it.
    private struct Field: Decodable {
        let type: String?
        let autocomplete: String?
        let error: String?
    }

    /// An outline as the snapshot script answers it: the elements it lists,
    /// the last of them, where a cut outline reads on, and how many frames of
    /// other sites it lists; or the error for a uid the page doesn't show.
    private struct Outline: Decodable {
        let url: String
        let title: String
        let outline: String?
        let elements: Int?
        let truncated: Bool?
        let last: String?
        let otherSites: Int?
        let matches: Int?
        let changes: Changes?
        let error: String?
        let uid: String?
    }

    /// How a read compared with the reader's last read of the document: not
    /// at all when there was none, and how many lines were added, changed and
    /// removed; `whole` when so much changed that the whole outline was read,
    /// and `summary` when a report gave only the counts.
    private struct Changes: Decodable {
        let compared: Bool
        let added: Int
        let changed: Int
        let removed: Int
        let whole: Bool?
        let summary: Bool?

        var counts: String { "\(added) added, \(changed) changed, \(removed) removed" }

        /// What the agent hears of the comparison, before the lines.
        var heading: String {
            if !compared { return "Ode has no earlier read of this document, so this is all of it." }
            if whole == true {
                return "Most of the page changed since your last read (\(counts)), so this is all of it."
            }
            if added + changed + removed == 0 { return "Nothing changed since your last read." }
            return "Changes since your last read: \(counts)."
        }
    }

    private struct ConsoleListing: Encodable {
        let sequence: Int64
        let level: String
        let text: String
        let source: String?
        let line: Int
    }

    /// Markdown as the Markdown script answers it: where it came from, the
    /// part asked for and the whole Markdown's length.
    private struct Markdown: Decodable {
        enum Source: String, Decodable {
            /// The page's own Markdown, which it links.
            case site
            /// A document that is text or Markdown itself.
            case document
            /// What Readability took for the page's main content.
            case main
            /// The whole page.
            case page

            func described(from path: String?) -> String {
                switch self {
                case .site: "the site's own Markdown, \(path ?? "")"
                case .document: "the document's own text"
                case .main: "the main content"
                case .page: "the whole page"
                }
            }
        }

        let url: String
        let title: String
        let source: Source
        let from: String?
        let markdown: String
        /// The Markdown's length and where this part of it ends, in UTF-16
        /// code units, as an offset counts.
        let total: Int
        let end: Int
        let truncated: Bool
    }

    /// A request as list_network_requests shows it, the values of its
    /// address's parameters that carry credentials hidden. What the page's
    /// engine doesn't know, such as the method and status WebKit never
    /// reports, is left out rather than shown as empty.
    struct RequestListing: Encodable {
        /// What an agent reads in place of a credential.
        static let hidden = "(hidden by Ode)"
        /// Parts of the names of headers and parameters whose values carry
        /// the person's sign-ins or keys, such as a session cookie, a bearer
        /// token, a CSRF token or a signed address's signature, which an
        /// agent never reads.
        private static let secretParts = [
            "auth", "token", "secret", "session", "cookie", "csrf", "xsrf", "passw", "pwd", "credential",
            "signature", "apikey", "api-key", "api_key", "otp",
        ]
        /// Whole names that carry them too, too short to look for inside
        /// others.
        private static let secretNames: Set<String> = ["key", "code", "sig", "sid", "jwt", "ticket"]

        let id: Int64
        let url: String
        let method: String?
        let type: String
        let status: Int?
        let failure: String?

        init(_ request: PageNetworkRequest) {
            id = request.sequence
            url = Self.shown(request.url)
            method = request.method.isEmpty ? nil : request.method
            type = request.resourceType
            status = request.status == 0 ? nil : request.status
            failure = request.failure
        }

        /// Whether a header or parameter named `name` carries a credential.
        static func carriesSecret(_ name: String) -> Bool {
            let name = name.lowercased()
            return secretNames.contains(name) || secretParts.contains { name.contains($0) }
        }

        /// `address` with the values of its parameters that carry credentials
        /// hidden, in its query and its fragment, and without any user and
        /// password it names; unchanged when it has none.
        static func shown(_ address: String) -> String {
            guard var components = URLComponents(string: address) else { return address }
            var changed = false
            if components.user != nil || components.password != nil {
                components.user = nil
                components.password = nil
                changed = true
            }
            let hide = { (items: [URLQueryItem]?) -> [URLQueryItem]? in
                guard let items, items.contains(where: { carriesSecret($0.name) && $0.value != nil }) else {
                    return nil
                }
                return items.map {
                    carriesSecret($0.name) && $0.value != nil ? URLQueryItem(name: $0.name, value: "hidden-by-Ode") : $0
                }
            }
            if let items = hide(components.queryItems) {
                components.queryItems = items
                changed = true
            }
            if let fragment = components.percentEncodedFragment, fragment.contains("=") {
                var inner = URLComponents()
                inner.percentEncodedQuery = fragment
                if let items = hide(inner.queryItems) {
                    inner.queryItems = items
                    components.percentEncodedFragment = inner.percentEncodedQuery
                    changed = true
                }
            }
            return changed ? components.string ?? address : address
        }
    }

    /// A request as get_network_request shows it, its credentials hidden and,
    /// as in the listing, what the engine doesn't know left out.
    struct RequestDetail: Encodable {
        let id: Int64
        let url: String
        let method: String?
        let type: String
        let status: Int?
        let mimeType: String?
        let requestHeaders: [String: String]?
        let responseHeaders: [String: String]?
        let durationMilliseconds: Double
        let bytes: Int64
        let failure: String?

        init(_ request: PageNetworkRequest) {
            let listing = RequestListing(request)
            id = listing.id
            url = listing.url
            method = listing.method
            type = listing.type
            status = listing.status
            mimeType = request.mimeType
            requestHeaders = Self.shown(request.requestHeaders)
            responseHeaders = Self.shown(request.responseHeaders)
            durationMilliseconds = request.duration
            bytes = request.bytes
            failure = request.failure
        }

        /// `headers` as an agent may read them, those that carry credentials
        /// hidden; nil when the engine reported none.
        private static func shown(_ headers: [PageHeader]) -> [String: String]? {
            guard !headers.isEmpty else { return nil }
            let shown = headers.map {
                ($0.name, RequestListing.carriesSecret($0.name) ? RequestListing.hidden : $0.value)
            }
            return Dictionary(shown, uniquingKeysWith: { first, _ in first })
        }
    }

    // MARK: - Static Variables

    private static let scriptTimeout = Duration.seconds(15)
    private static let settleTimeout = Duration.seconds(15)
    private static let inputTimeout = Duration.seconds(10)
    /// How long a page has after input, and any load it started, to change
    /// before a report reads it.
    private static let reportSettle = Duration.milliseconds(300)
    /// How long after input a page is given for a load the input started to
    /// begin, as a click on a link or a submit button does.
    private static let loadGrace = Duration.seconds(1)
    private static let untrustedNote =
        "This page’s engine took the input as script events, which some pages ignore. If nothing changed, try another way."
    private static let downloadNote =
        "A download from this tab waits for the person to approve it in Ode, and isn’t saved until they do."
    private static let markdownNote =
        "Nothing in this Markdown has a uid. To act on the page, use take_snapshot with find or filter."
    private static let skeletonNote =
        "Headings and landmarks only, each with how many elements it holds. To read one, or a heading’s section, call take_snapshot with its uid."
    private static let otherSitesNote =
        "Frames from other sites aren’t read; each shows its address. To read one, open its address with open_tab, which asks the person first for a site you haven’t opened."

    // MARK: - Actions - Reading

    func takeSnapshot(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let arguments = try call.arguments(Reading.self)
        let cap = BrowserAgentPageScript.cap(arguments.maxChars)
        let reading = BrowserAgentPageScript.Reading(
            reader: call.sessionID.uuidString, depth: arguments.depth.map { Int(min(max($0, 0), 10_000)) },
            filter: arguments.filter.flatMap { $0.isEmpty ? nil : $0 },
            find: arguments.find.flatMap { $0.isEmpty ? nil : $0 }, maxChars: cap,
            uid: arguments.uid.flatMap { $0.isEmpty ? nil : $0 },
            after: arguments.after.flatMap { $0.isEmpty ? nil : $0 },
            skeleton: arguments.skeleton == true, changes: arguments.changes == true)
        return try await serially(on: arguments.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: arguments.tab, call)
            let outline = try await self.run(.snapshot(reading), on: page, call).decoded(Outline.self)
            if let error = outline.error { throw Self.unread(outline.uid ?? "", error) }
            let body = outline.outline ?? ""
            let within = reading.uid.map { " · inside \($0)" } ?? ""
            var text =
                "page: \(outline.title) · \(outline.url)\(within) · \(outline.elements ?? 0) elements · \(body.count) chars"
            if reading.skeleton { text += "\n\(Self.skeletonNote)" }
            if let changes = outline.changes { text += "\n\(changes.heading)" }
            if let find = reading.find { text += "\n\(outline.matches ?? 0) matches for \"\(find)\"" }
            if !body.isEmpty { text += "\n\n\(body)" }
            if outline.truncated == true {
                text +=
                    "\n\n"
                    + (reading.changes
                        ? "(Changes were cut at max_chars \(cap). The earlier read is kept; repeat take_snapshot with changes and a larger max_chars.)"
                        : Self.cutNote(at: cap, after: outline.last))
            }
            if (outline.otherSites ?? 0) > 0 { text += "\n\n\(Self.otherSitesNote)" }
            if self.awaitsPerson(arguments.tab) { text += "\n\n\(Self.downloadNote)" }
            return .message(text)
        }
    }

    func readPageText(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let reading = try call.arguments(TextReading.self)
        let limit = reading.limit ?? 20_000
        guard (1_000...100_000).contains(limit) else {
            throw .invalidArguments("max_chars must be between 1000 and 100000.")
        }
        return try await serially(on: reading.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: reading.tab, call)
            let read = try await self.run(BrowserAgentPageScript.readText(limit: limit), on: page, call).decoded(
                PageText.self)
            var text = "Page: \(read.title)\nAddress: \(read.url)\n\n\(read.text)"
            if read.truncated { text += "\n\n(The text was cut short at \(limit) characters.)" }
            return .message(text)
        }
    }

    /// What an agent hears when an outline stopped at `cap` characters after
    /// the element `last`: how to read on, and how to read less.
    private static func cutNote(at cap: Int, after last: String?) -> String {
        let reading = last.map { "To read on, call take_snapshot with after: \"\($0)\". " } ?? ""
        return "(The outline was cut at max_chars \(cap). \(reading)"
            + "To read less, use skeleton, uid, find or filter, or bound depth. Scrolling doesn’t change the outline.)"
    }

    /// The failure for a uid an outline can't start from: one the page never
    /// named or no longer has, or one it doesn't show now.
    private static func unread(_ uid: String, _ error: String) -> BrowserAgentFailure {
        error == "hidden"
            ? .refused("The page doesn’t show \(uid) now. Take a new snapshot and use its uids.")
            : .unknownElement(uid)
    }

    func readPage(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let reading = try call.arguments(MarkdownReading.self)
        let cap = BrowserAgentPageScript.cap(reading.maxChars)
        let offset = Int(min(max(reading.offset ?? 0, 0), 100_000_000))
        let script = BrowserAgentPageScript.markdown(fullPage: reading.fullPage == true, offset: offset, maxChars: cap)
        return try await serially(on: reading.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: reading.tab, call)
            let markdown = try await self.run(script, on: page, call).decoded(Markdown.self)
            let part = offset > 0 ? " from character \(offset)" : ""
            var text =
                "page: \(markdown.title) · \(markdown.url) · Markdown of \(markdown.source.described(from: markdown.from))"
                + "\(part) · \(max(0, markdown.end - offset)) of \(markdown.total) chars\n\n\(markdown.markdown)"
            if markdown.truncated {
                text +=
                    "\n\n(The Markdown was cut at max_chars \(cap). To read on, call read_page with offset: \(markdown.end).)"
            }
            text += "\n\n\(Self.markdownNote)"
            if self.awaitsPerson(reading.tab) { text += "\n\n\(Self.downloadNote)" }
            return .message(text)
        }
    }

    // MARK: - Actions - Input

    func click(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let click = try call.arguments(Click.self)
        return try await serially(on: click.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: click.tab, call)
            let located = try await self.locate(click.uid, on: page, call)
            let point = PagePoint(x: located.x, y: located.y)
            page.page.pointAgent(at: point, presses: true)
            let delivered = try await self.deliver(
                .click(at: point, button: click.button?.pointer ?? .primary, count: click.double == true ? 2 : 1),
                to: page, tab: click.tab, call)
            let message = self.done("Clicked the \(located.tag) \(click.uid).", delivered, tab: click.tab)
            return .message(await self.reported(message, click.report, on: page, call))
        }
    }

    func hover(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let reference = try call.arguments(ElementReference.self)
        return try await serially(on: reference.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: reference.tab, call)
            let located = try await self.locate(reference.uid, on: page, call)
            let point = PagePoint(x: located.x, y: located.y)
            page.page.pointAgent(at: point, presses: false)
            let delivered = try await self.deliver(.hover(at: point), to: page, tab: reference.tab, call)
            return .message(
                self.done("The pointer is over the \(located.tag) \(reference.uid).", delivered, tab: reference.tab))
        }
    }

    func fill(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let fill = try call.arguments(Fill.self)
        return try await serially(on: fill.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: fill.tab, call)
            try await self.refuseProtected(fill.uid, value: fill.value, on: page, call)
            // The pointer goes to the field first, as a person's would.
            if let located = try? await self.locate(fill.uid, on: page, call) {
                page.page.pointAgent(at: PagePoint(x: located.x, y: located.y), presses: true)
            }
            let prepared = try await self.run(
                BrowserAgentPageScript.prepareFill(fill.uid, value: fill.value), on: page, call)
            if let refusal = BrowserAgentFillRefusal.named(prepared["error"]?.string) {
                throw refusal.failure(uid: fill.uid, value: fill.value)
            }
            if let chosen = prepared["chosen"]?.string {
                return .message(await self.reported("Chose \(chosen).", fill.report, on: page, call))
            }
            guard !fill.value.isEmpty else {
                return .message(await self.reported("Cleared \(fill.uid).", fill.report, on: page, call))
            }
            let delivered = try await self.deliver(.type(fill.value), to: page, tab: fill.tab, call)
            let message = self.done("Filled \(fill.uid).", delivered, tab: fill.tab)
            return .message(await self.reported(message, fill.report, on: page, call))
        }
    }

    func typeText(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let typing = try call.arguments(Typing.self)
        return try await serially(on: typing.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: typing.tab, call)
            try await self.refuseProtected(nil, value: typing.text, on: page, call)
            let delivered = try await self.deliver(.type(typing.text), to: page, tab: typing.tab, call)
            return .message(self.done("Typed the text.", delivered, tab: typing.tab))
        }
    }

    func pressKey(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let press = try call.arguments(KeyPress.self)
        guard let key = BrowserAgentKey.named(press.key) else {
            throw .invalidArguments(
                "\(press.key) is not a key Ode knows; use a KeyboardEvent key such as Enter or a.")
        }
        let modifiers = (press.modifiers ?? []).reduce(into: KeyModifiers()) { $0.formUnion($1.keys) }
        return try await serially(on: press.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: press.tab, call)
            // A key that types a character is text like any other; Enter only submits.
            if let text = key.text, text != "\r" { try await self.refuseProtected(nil, value: text, on: page, call) }
            let delivered = try await self.deliver(
                .press(key.pageKey, modifiers: modifiers), to: page, tab: press.tab, call)
            let message = self.done("Pressed \(press.key).", delivered, tab: press.tab)
            return .message(await self.reported(message, press.report, on: page, call))
        }
    }

    func scroll(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let scrolling = try call.arguments(Scrolling.self)
        return try await serially(on: scrolling.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: scrolling.tab, call)
            var point = PagePoint(x: 10, y: 10)
            if let uid = scrolling.uid {
                let located = try await self.locate(uid, on: page, call)
                point = PagePoint(x: located.x, y: located.y)
                page.page.pointAgent(at: point, presses: false)
            }
            let (dx, dy) = (scrolling.dx ?? 0, scrolling.dy ?? 0)
            guard dx != 0 || dy != 0 else { return .message("Scrolled \(scrolling.uid ?? "the page") into view.") }
            let delivered = try await self.deliver(
                .scroll(at: point, deltaX: dx, deltaY: dy), to: page, tab: scrolling.tab, call)
            return .message(self.done("Scrolled.", delivered, tab: scrolling.tab))
        }
    }

    func waitFor(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let waiting = try call.arguments(Waiting.self)
        guard waiting.text == nil || waiting.url == nil else { throw .invalidArguments("give text or url, not both.") }
        let timeout = Duration.milliseconds(Int(min(max(waiting.timeout ?? 10_000, 0), 60_000)))
        return try await serially(on: waiting.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: waiting.tab, call)
            let deadline = ContinuousClock.now + timeout
            repeat {
                try self.validate(page, call)
                if let address = waiting.url {
                    if page.page.live.url?.contains(address) == true {
                        return .message("The tab is at \(page.page.live.url ?? address).")
                    }
                } else if (try? await self.run(BrowserAgentPageScript.shows(waiting.text), on: page, call))
                    == .bool(true)
                {
                    return .message(waiting.text.map { "The page shows \($0)." } ?? "The page finished loading.")
                }
                try? await Task.sleep(for: .milliseconds(250))
            } while ContinuousClock.now < deadline
            if let address = waiting.url {
                throw .refused("The tab's address didn't come to contain \(address) in time.")
            }
            throw .timedOut
        }
    }

    // MARK: - Actions - Dialogs

    /// Answers the page's alert, confirm or prompt, never a question about
    /// leaving the page, which keeps the person's unsaved work theirs. It
    /// waits for no other call on the tab, since the dialog may be what holds
    /// one up.
    func handleDialog(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let answer = try call.arguments(DialogAnswer.self)
        let page = try page(for: answer.tab, call)
        guard let asked = page.scriptDialog, asked.question.kind != .beforeUnload else {
            throw .refused("The page shows no dialog an agent may answer.")
        }
        page.corePage.answer(AnswerScriptDialog(promptID: asked.promptID, accepted: answer.accept, text: answer.text))
        return .message(answer.accept ? "Accepted the page's dialog." : "Dismissed the page's dialog.")
    }

    // MARK: - Actions - Activity

    func listConsoleMessages(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let since = try call.arguments(Since.self)
        return try await serially(on: since.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: since.tab, call)
            try self.validate(page, call)
            let log = page.engine.console(after: since.since ?? 0)
            let messages = log.messages.map {
                ConsoleListing(
                    sequence: $0.sequence, level: String(describing: $0.level), text: $0.text, source: $0.source,
                    line: $0.line)
            }
            return .data(["messages": messages])
        }
    }

    func listNetworkRequests(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let since = try call.arguments(Since.self)
        return try await serially(on: since.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: since.tab, call)
            try self.validate(page, call)
            let log = page.engine.network(after: since.since ?? 0)
            let requests = log.requests.map(RequestListing.init)
            return .data(["requests": requests])
        }
    }

    func getNetworkRequest(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let reference = try call.arguments(RequestReference.self)
        return try await serially(on: reference.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            let page = try await self.settledPage(for: reference.tab, call)
            try self.validate(page, call)
            guard
                let request = page.engine.network(after: reference.id - 1).requests.first(where: {
                    $0.sequence == reference.id
                })
            else { throw .refused("The tab kept no request \(reference.id).") }
            return .data(RequestDetail(request))
        }
    }

    // MARK: - Actions - Scripts

    func evaluateScript(_ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> AgentToolResult {
        let script = try call.arguments(Script.self)
        guard core.state.agentPreferences.runsScripts else { throw .scriptsOff }
        return try await serially(on: script.tab) { () async throws(BrowserAgentFailure) -> AgentToolResult in
            guard self.core.state.agentPreferences.runsScripts else { throw .scriptsOff }
            let page = try await self.settledPage(for: script.tab, call)
            try self.validate(page, call)
            guard self.core.state.agentPreferences.runsScripts else { throw .scriptsOff }
            guard
                let evaluated = await page.engine.evaluate(script.function, in: .page, timeout: Self.scriptTimeout)
            else { throw .timedOut }
            try BrowserAgentFailure.checkCancellation()
            if let error = evaluated.error { throw .script(error) }
            return .message(evaluated.json ?? "null")
        }
    }

    // MARK: - Actions - Pages

    /// The live page of tab `tabID`, which the agent uses from now on, loaded
    /// and rendering for it whether or not a window shows it. Its console and
    /// network are kept from the agent's first use of it, so a tab the agent
    /// opens is kept from its first load.
    func page(for tabID: UUID, _ call: BrowserAgentCall) throws(BrowserAgentFailure) -> BrowserPage {
        let (space, tab) = try claim(tabID, call)
        guard let page = application.pages.agentPage(for: tab, in: space) else { throw .noPage }
        guard page.webKitView != nil else { throw .navigationBoundaryUnavailable }
        guard Self.showsWebPage(page.live.url) else { throw .notWebPage }
        if call.link.observedPages[tabID] != page.enginePage.id, page.enginePage.observeActivity(true) {
            call.link.observedPages[tabID] = page.enginePage.id
        }
        return page
    }

    /// The live page of tab `tabID`, as `page(for:)` gives it, once it shows a
    /// document: one that was just loaded for the agent, or is still on its
    /// way, settles first, for up to `settleTimeout`. Just after the agent's
    /// input, a load the input starts is waited for too.
    private func settledPage(for tabID: UUID, _ call: BrowserAgentCall) async throws(BrowserAgentFailure) -> PageAccess
    {
        let page = try page(for: tabID, call)
        return try await settledPage(PageAccess(tabID: tabID, page: page, engine: page.enginePage), call)
    }

    private func settledPage(_ access: PageAccess, _ call: BrowserAgentCall) async throws(BrowserAgentFailure)
        -> PageAccess
    {
        let page = access.page
        let tabID = access.tabID
        try validate(access, call)
        if let input = call.link.lastInput.removeValue(forKey: tabID) {
            while !page.live.isLoading, page.live.pendingURL == nil, ContinuousClock.now < input + Self.loadGrace {
                try validate(access, call)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        let deadline = ContinuousClock.now + Self.settleTimeout
        while page.committedNavigationCount == 0 || page.live.isLoading || page.live.pendingURL != nil,
            ContinuousClock.now < deadline
        {
            try validate(access, call)
            try? await Task.sleep(for: .milliseconds(100))
        }
        try validate(access, call)
        // The page renders for the agent from now on, at the size of the window
        // over its Space, once its engine made it; a page still being made is
        // asked again on the agent's next call.
        // A load may have left the web for a page agents can't use.
        guard Self.showsWebPage(page.live.url) else { throw .notWebPage }
        if call.link.heldPages[tabID] != page.enginePage.id {
            let size =
                frontWindow(over: try validate(access, call))?.pages.presentationWindow?.contentLayoutRect.size
                ?? CGSize(width: 1280, height: 800)
            if page.enginePage.holdRendering(true, size: size) {
                call.link.heldPages[tabID] = page.enginePage.id
                // A page that took a size lays out again before it is read.
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        try validate(access, call)
        return access
    }

    /// Rechecks live core reach and the captured resident/engine identity at
    /// each submission boundary. In particular, this must never send a claim:
    /// a revoked-and-restored Space does not restore an in-flight call's claim.
    @discardableResult
    private func validate(_ access: PageAccess, _ call: BrowserAgentCall) throws(BrowserAgentFailure) -> SpaceModel {
        let reach = try reach(call)
        guard let workspaceID = reach.workspaceID,
            let reached = reach.spaces.first(where: {
                !$0.isLocked && $0.tabs.contains { $0.tabID == access.tabID && $0.claimed }
            }),
            let space = core.state.workspaces[workspaceID]?.spaces.model(reached.spaceID)
        else { throw .rejected(.agentTabUnavailable(AgentTabUnavailable(tabID: access.tabID))) }
        guard application.pages.residentPage(ofTab: access.tabID) === access.page,
            access.page.enginePage === access.engine, !access.engine.closed
        else { throw .noPage }
        guard
            Self.supportsAgentPage(
                residentIsWebKit: access.page.webKitView != nil,
                engines: core.state.engines?.engines.map(\.kind) ?? [])
        else { throw .navigationBoundaryUnavailable }
        guard Self.showsWebPage(access.page.live.url) else { throw .notWebPage }
        return space
    }

    /// Whether `address` shows a web page, or a blank one or none yet, which
    /// an agent may use, rather than one of the browser's own, an extension's
    /// or a file.
    private static func showsWebPage(_ address: String?) -> Bool {
        guard let address else { return true }
        guard address != "about:blank" else { return true }
        let scheme = URL(string: address)?.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    /// What `script` answered in the agent's world of `page`.
    private func run(_ script: BrowserAgentPageScript, on page: PageAccess, _ call: BrowserAgentCall)
        async throws(BrowserAgentFailure)
        -> AgentJSON
    {
        try validate(page, call)
        guard let evaluated = await page.engine.evaluate(script.source, in: .agent, timeout: Self.scriptTimeout)
        else {
            throw page.page.scriptDialog.map(BrowserAgentFailure.dialog) ?? .timedOut
        }
        try BrowserAgentFailure.checkCancellation()
        if let error = evaluated.error { throw .script(error) }
        guard let json = evaluated.json, let value = try? JSONDecoder().decode(AgentJSON.self, from: Data(json.utf8))
        else {
            return .null
        }
        return value
    }

    private func locate(_ uid: String, on page: PageAccess, _ call: BrowserAgentCall) async throws(BrowserAgentFailure)
        -> Located
    {
        let answer = try await run(BrowserAgentPageScript.locate(uid), on: page, call)
        guard answer["error"] == nil, let located = try? answer.decoded(as: Located.self) else {
            throw .unknownElement(uid)
        }
        return located
    }

    /// Delivers `input` to `page` of tab `tabID`, which the agent's next call
    /// on the tab gives a moment to start a load.
    private func deliver(_ input: EnginePageInput, to page: PageAccess, tab tabID: UUID, _ call: BrowserAgentCall)
        async throws(BrowserAgentFailure) -> PageInputDelivered
    {
        try validate(page, call)
        guard let delivered = await page.engine.deliver(input, timeout: Self.inputTimeout) else {
            // Input may still start a load after its acknowledgement wait ends,
            // and input that opens a dialog waits on its answer.
            call.link.lastInput[tabID] = .now
            if let asked = page.page.scriptDialog { throw .dialog(asked) }
            throw .inputUnconfirmed
        }
        guard delivered.delivered else { throw .refused("The page did not take the input.") }
        call.link.lastInput[tabID] = .now
        return delivered
    }

    /// Refuses to write `value` into the field `uid` names, or without one
    /// the field the page's focus is in, when it is one only the person
    /// fills, before any of it is written.
    private func refuseProtected(_ uid: String?, value: String, on page: PageAccess, _ call: BrowserAgentCall)
        async throws(BrowserAgentFailure)
    {
        let field = try await run(BrowserAgentPageScript.field(uid), on: page, call).decoded(Field.self)
        let refusal =
            BrowserAgentFillRefusal.named(field.error)
            ?? BrowserAgentFillRefusal.protecting(type: field.type ?? "", autocomplete: field.autocomplete ?? "")
        if let refusal { throw refusal.failure(uid: uid ?? "", value: value) }
    }

    /// `message`, followed when the agent asked for a `report` by what the
    /// input changed on tab `tabID`'s page since the agent last read it, once
    /// a load the input started has finished and the page had a moment to
    /// change: the lines, within `reportLimit` characters, or only how many.
    /// A report that holds every change counts as the agent's latest read.
    private func reported(_ message: String, _ report: Bool?, on access: PageAccess, _ call: BrowserAgentCall) async
        -> String
    {
        guard report == true else { return message }
        let failed = "\(message)\n\nOde couldn’t read what changed. take_snapshot reads the page."
        guard let page = try? await settledPage(access, call) else { return failed }
        try? await Task.sleep(for: Self.reportSettle)
        var reading = BrowserAgentPageScript.Reading(
            reader: call.sessionID.uuidString, maxChars: BrowserAgentPageScript.reportLimit)
        reading.report = true
        guard let outline = try? await run(.snapshot(reading), on: page, call).decoded(Outline.self),
            let changes = outline.changes
        else { return failed }
        let lines = outline.outline.map { $0.isEmpty ? "" : "\n\n\($0)" } ?? ""
        if !changes.compared {
            return "\(message)\n\nOde has no earlier read of this page to compare with: \(outline.title) · "
                + "\(outline.url). take_snapshot reads it."
        }
        if changes.summary == true {
            return "\(message)\n\nMuch of the page changed (\(changes.counts)). take_snapshot with changes reads it."
        }
        return "\(message)\n\n\(changes.heading)\(lines)"
    }

    /// Whether a download from tab `tabID` waits for the person, who answers
    /// for every download from a tab an agent uses.
    private func awaitsPerson(_ tabID: UUID) -> Bool {
        application.downloadPrompts.awaitsPerson(inTab: tabID)
    }

    private func done(_ message: String, _ delivered: PageInputDelivered, tab tabID: UUID) -> String {
        var text = delivered.trusted ? message : "\(message) \(Self.untrustedNote)"
        if awaitsPerson(tabID) { text += " \(Self.downloadNote)" }
        return text
    }
}
