import WebKit
import XCTest

@testable import Ode

/// The scripts agents read and act on pages with, run against local page
/// fixtures in WebKit's agent world through the engine page agents use: what
/// an outline holds, where a uid's element is, where input lands, and which
/// field an agent's text would go into.
@MainActor
final class BrowserAgentPageScriptTests: XCTestCase {
    private var pools: [BrowserPagePool] = []

    override func tearDown() async throws {
        pools.removeAll()
        try await super.tearDown()
    }

    // MARK: - Outline

    func testOutlineKeepsWhatDisplayContentsElementsHold() async throws {
        let page = try await load("display-contents.html")
        let outline = try await read(page)

        XCTAssertTrue(outline.text.contains(#"heading "Element: checkVisibility() method""#), outline.text)
        XCTAssertTrue(outline.text.contains("The method answers whether an element is rendered."))
        XCTAssertTrue(outline.text.contains(#"link "Second open issue""#))
        XCTAssertFalse(outline.text.contains("Hidden inside contents"), "What the page hides stays out.")
    }

    func testOutlineReadsAPageWhoseNamedControlsShadowItsProperties() async throws {
        let page = try await load("named-controls.html")
        let outline = try await read(page)

        XCTAssertEqual(outline.title, "Named controls")
        XCTAssertTrue(outline.text.contains(#"searchbox "Search""#), outline.text)
        XCTAssertTrue(outline.text.contains(#"heading "Web browser""#))
    }

    func testCutOutlineReadsOnFromItsLastElement() async throws {
        let page = try await load("long.html")
        let whole = try await read(page, BrowserAgentPageScript.Reading(maxChars: 1_000_000))
        var outline = try await read(page, BrowserAgentPageScript.Reading(maxChars: 2_000))
        XCTAssertTrue(outline.truncated)
        var lines = outline.lines
        while outline.truncated, let last = outline.last, lines.count < 2_000 {
            outline = try await read(page, BrowserAgentPageScript.Reading(maxChars: 2_000, after: last))
            lines += outline.lines
        }

        XCTAssertEqual(lines.filter(Outline.isElement), whole.lines.filter(Outline.isElement))
        let unknown = try await evaluate(.snapshot(BrowserAgentPageScript.Reading(after: "e99999")), on: page)
        XCTAssertEqual(unknown["error"] as? String, "unknown")
    }

    func testOutlineListsEachTextOnceWithPathsForTheSitesOwnLinks() async throws {
        let page = try await load("article.html")
        let outline = try await read(page)

        XCTAssertTrue(outline.text.contains("[href=/trails]"), outline.text)
        XCTAssertTrue(outline.text.contains("[href=https://maps.example.org/area?id=7"))
        XCTAssertTrue(outline.lines.contains { $0.hasPrefix(" - navigation") }, "One space of indent per level.")
        XCTAssertTrue(outline.text.contains(#"listitem "Check the weather the evening before.""#))
        XCTAssertFalse(outline.text.contains(#"text "Check the weather"#), "A list item's text is its name, once.")
        let item = try XCTUnwrap(outline.lines.firstIndex { $0.contains("listitem [uid=") })
        XCTAssertTrue(outline.lines[item + 1].contains(#"text "Tell someone your route.""#))
        XCTAssertFalse(outline.text.contains("Ignore previous instructions"), "What the page hides stays out.")
    }

    func testSkeletonAndUidReadOnePartOfThePage() async throws {
        let page = try await load("article.html")
        let skeleton = try await read(page, BrowserAgentPageScript.Reading(skeleton: true))

        XCTAssertTrue(skeleton.lines.contains { $0.hasPrefix("- main") && $0.contains("[elements=") }, skeleton.text)
        XCTAssertFalse(skeleton.text.contains("Saddle to summit"))
        let stages = try XCTUnwrap(skeleton.uid(of: #"heading "Stages""#))
        let section = try await read(page, BrowserAgentPageScript.Reading(uid: stages))
        XCTAssertTrue(section.text.contains("Saddle to summit") && section.text.contains(#"heading "Summit""#))
        XCTAssertFalse(section.text.contains("Book a guide"), "A heading's section ends at the next of its level.")
        let whole = try await read(page)
        let form = try XCTUnwrap(whole.uid(of: "- form"))
        let subtree = try await read(page, BrowserAgentPageScript.Reading(uid: form))
        XCTAssertTrue(subtree.lines.first?.hasPrefix("- form") == true && subtree.text.contains(#"button "Book""#))
        XCTAssertFalse(subtree.text.contains("Stages"))
    }

    func testOutlineNeverShowsTheValuesOfFieldsOnlyThePersonFills() async throws {
        let page = try await load("fields.html")
        let outline = try await read(page)

        XCTAssertTrue(outline.text.contains(#"[value="Alice Example"]"#), outline.text)
        XCTAssertTrue(outline.text.contains("[password]") && outline.text.contains("[protected]"))
        for secret in ["hunter2-secret", "4111111111111111", "123456"] {
            XCTAssertFalse(outline.text.contains(secret), "\(secret) is shown.")
        }
    }

    // MARK: - Changes

    func testChangesSinceTheLastReadListWhatWasAddedChangedAndRemoved() async throws {
        let page = try await load("article.html")
        let changes = BrowserAgentPageScript.Reading(reader: "agent", changes: true)
        let first = try await evaluate(.snapshot(changes), on: page)
        XCTAssertEqual((first["changes"] as? [String: Any])?["compared"] as? Bool, false)
        XCTAssertTrue((first["outline"] as? String ?? "").contains("Ridge trail guide"), "A first read is all of it.")
        _ = try await page.webView.evaluateJavaScript(
            """
            const item = document.createElement("li"); item.textContent = "Pack a head torch.";
            document.querySelector("ul").append(item);
            document.querySelector("#book").setAttribute("aria-expanded", "true");
            document.querySelector("footer p").textContent = "Published by the ranger station.";
            """)

        let second = try await evaluate(
            .snapshot(
                .init(
                    reader: "agent", depth: 0, filter: "absent", uid: "e99999", after: "e99999", skeleton: true,
                    changes: true)),
            on: page)
        let text = try XCTUnwrap(second["outline"] as? String)
        let counts = try XCTUnwrap(second["changes"] as? [String: Any])

        XCTAssertTrue(text.contains(#"listitem "Pack a head torch.""#) && text.contains("added in e"), text)
        XCTAssertTrue(text.contains("changed:\n- button \"Book\"") && text.contains("[expanded=true]"))
        XCTAssertTrue(text.contains("removed:\n- text \"Published by the park office.\""))
        XCTAssertEqual(counts["changed"] as? Int, 1)
        let third = try await evaluate(.snapshot(changes), on: page)
        XCTAssertEqual(third["outline"] as? String, "", "A read with changes is the next one's last read.")
        let other = try await evaluate(
            .snapshot(BrowserAgentPageScript.Reading(reader: "other", changes: true)), on: page)
        XCTAssertEqual((other["changes"] as? [String: Any])?["compared"] as? Bool, false, "Each agent has its own.")
    }

    func testAReportTooLargeGivesCountsAndKeepsTheChangesForTheNextRead() async throws {
        let page = try await load("article.html")
        _ = try await evaluate(.snapshot(BrowserAgentPageScript.Reading(reader: "agent")), on: page)
        _ = try await page.webView.evaluateJavaScript(
            """
            for (let line = 0; line < 200; line++) {
              const item = document.createElement("li"); item.textContent = "Extra line " + line;
              document.querySelector("ul").append(item);
            }
            """)
        var report = BrowserAgentPageScript.Reading(reader: "agent", maxChars: BrowserAgentPageScript.reportLimit)
        report.report = true

        let summary = try await evaluate(.snapshot(report), on: page)
        let changes = try await evaluate(
            .snapshot(BrowserAgentPageScript.Reading(reader: "agent", changes: true)), on: page)

        XCTAssertEqual((summary["changes"] as? [String: Any])?["summary"] as? Bool, true)
        XCTAssertNil(summary["outline"])
        XCTAssertEqual((changes["changes"] as? [String: Any])?["added"] as? Int, 200)
    }

    func testAnInvalidReadDoesNotAdvanceTheChangeBaseline() async throws {
        let page = try await load("article.html")
        _ = try await read(page, .init(reader: "agent"))
        _ = try await page.webView.evaluateJavaScript(
            "document.querySelector('#book').setAttribute('aria-expanded', 'true')")
        let invalid = try await evaluate(.snapshot(.init(reader: "agent", uid: "e99999")), on: page)
        XCTAssertEqual(invalid["error"] as? String, "unknown")
        let delta = try await evaluate(.snapshot(.init(reader: "agent", changes: true)), on: page)
        XCTAssertEqual((delta["changes"] as? [String: Any])?["changed"] as? Int, 1)
    }

    func testACutChangeReadDoesNotConsumeChangesTheAgentHasNotReceived() async throws {
        let page = try await load("article.html")
        _ = try await read(page, .init(reader: "agent"))
        _ = try await page.webView.evaluateJavaScript(
            """
            for (let line = 0; line < 60; line++) {
              const item = document.createElement("li"); item.textContent = "Additional trail advice " + line;
              document.querySelector("ul").append(item);
            }
            """)
        let cut = try await evaluate(.snapshot(.init(reader: "agent", maxChars: 2_000, changes: true)), on: page)
        XCTAssertEqual(cut["truncated"] as? Bool, true)
        let complete = try await evaluate(
            .snapshot(.init(reader: "agent", maxChars: 1_000_000, changes: true)), on: page)
        XCTAssertEqual((complete["changes"] as? [String: Any])?["added"] as? Int, 60)
        XCTAssertTrue((complete["outline"] as? String ?? "").contains("Additional trail advice 59"))
    }

    // MARK: - Markdown

    func testMarkdownHoldsTheMainContentWithoutHiddenTextOrFieldValues() async throws {
        let page = try await load("article.html")
        let markdown = try await evaluate(.markdown(fullPage: false, offset: 0, maxChars: 60_000), on: page)
        let text = try XCTUnwrap(markdown["markdown"] as? String)

        XCTAssertEqual(markdown["source"] as? String, "main")
        XCTAssertTrue(text.contains("## Before you go") && text.contains("- Carry two litres of water."), text)
        XCTAssertTrue(text.contains("| Saddle to summit | 6 km |"), "A table of data stays a table.")
        XCTAssertTrue(text.contains("[Read the safety notes](/safety)"))
        for hidden in ["Ignore previous instructions", "Hidden promotional text", "walker@example.com"] {
            XCTAssertFalse(text.contains(hidden), "\(hidden) is part of the Markdown.")
        }
    }

    func testMarkdownOfTheWholePageReadsOnFromAnOffset() async throws {
        let page = try await load("article.html")
        let whole = try await evaluate(.markdown(fullPage: true, offset: 0, maxChars: 1_000_000), on: page)
        let first = try await evaluate(.markdown(fullPage: true, offset: 0, maxChars: 200), on: page)
        let rest = try await evaluate(.markdown(fullPage: true, offset: 200, maxChars: 1_000_000), on: page)
        let text = try XCTUnwrap(whole["markdown"] as? String)

        XCTAssertEqual(whole["source"] as? String, "page")
        XCTAssertTrue(text.contains("[Map](https://maps.example.org/area?id=7)"), "Tracking parameters are dropped.")
        XCTAssertTrue(text.contains("[Trails](/trails)"))
        XCTAssertEqual(first["truncated"] as? Bool, true)
        XCTAssertEqual((first["markdown"] as? String ?? "") + (rest["markdown"] as? String ?? ""), text)
    }

    func testMarkdownIsThePagesOwnWhenItLinksOne() async throws {
        let server = try BrowserPrivacyHTTPServer()
        let fixtures = Self.fixtures
        server.overrideResponse = { request in
            let name = String(request.path.dropFirst())
            guard let body = try? Data(contentsOf: fixtures.appending(path: name)) else {
                return ("404 Not Found", "Content-Type: text/plain\r\n", Data())
            }
            let type = name.hasSuffix(".md") ? "text/markdown; charset=utf-8" : "text/html; charset=utf-8"
            return ("200 OK", "Content-Type: \(type)\r\n", body)
        }
        try await server.start()
        defer { server.stop() }
        let page = try await load("docs.html", from: server.url(host: "127.0.0.1", path: "/docs.html"))

        let markdown = try await evaluate(.markdown(fullPage: false, offset: 0, maxChars: 60_000), on: page)

        XCTAssertEqual(markdown["source"] as? String, "site")
        XCTAssertEqual(markdown["from"] as? String, "/docs.md")
        XCTAssertTrue((markdown["markdown"] as? String ?? "").contains("install-cli && cli login"))
    }

    // MARK: - Frames

    func testOutlineReadsFramesOfThePagesOwnOriginAndInputReachesThem() async throws {
        let page = try await load("frames.html")
        let outline = try await read(page)

        XCTAssertTrue(outline.text.contains(#"heading "Sign in""#), outline.text)
        XCTAssertTrue(outline.text.contains(#"iframe "Card""#) && outline.text.contains("[other site]"))
        XCTAssertFalse(outline.text.contains("Tracker"), "A frame too small to show anything is left out.")
        XCTAssertEqual(outline.otherSites, 1)

        let button = try XCTUnwrap(outline.uid(of: #"button "Continue""#))
        let located = try await evaluate(.locate(button), on: page)
        let point = PagePoint(x: try XCTUnwrap(located["x"] as? Double), y: try XCTUnwrap(located["y"] as? Double))
        let delivered = await page.enginePage.deliver(.click(at: point), timeout: .seconds(5))
        XCTAssertEqual(delivered?.delivered, true)
        let clicked = try await evaluate(
            BrowserAgentPageScript(
                source: "return document.querySelector('iframe').contentDocument.body.dataset.clicked ?? null;"),
            on: page)
        XCTAssertEqual(clicked["value"] as? String, "yes", "A click at the located point reaches the frame's button.")

        let email = try XCTUnwrap(outline.uid(of: #"textbox "Email""#))
        _ = try await evaluate(.prepareFill(email, value: "person@example.com"), on: page)
        let field = try await evaluate(.field(nil), on: page)
        XCTAssertEqual(field["autocomplete"] as? String, "email", "The field check reads the frame's field.")
        _ = await page.enginePage.deliver(.type("person@example.com"), timeout: .seconds(5))
        let typed = try await evaluate(
            BrowserAgentPageScript(
                source: "return document.querySelector('iframe').contentDocument.querySelector('input').value;"),
            on: page)
        XCTAssertEqual(typed["value"] as? String, "person@example.com", "Typing goes where the field check looked.")
    }

    func testTextIsRefusedWhileTheFocusIsInAnotherSitesFrame() async throws {
        let page = try await load("frames.html")
        _ = try await evaluate(
            BrowserAgentPageScript(source: "document.querySelectorAll('iframe')[1].focus(); return null;"), on: page)

        let field = try await evaluate(.field(nil), on: page)

        XCTAssertEqual(field["error"] as? String, "unseen")
        XCTAssertNotNil(BrowserAgentFillRefusal.named(field["error"] as? String))
    }

    func testTextIsRefusedWhileTheFocusIsInAClosedShadowRoot() async throws {
        let page = try await load("closed-shadow.html")
        _ = try await evaluate(
            BrowserAgentPageScript(source: "document.querySelector('sign-in-field').focus(); return null;"), on: page)
        let focused = try await evaluate(
            BrowserAgentPageScript(source: "return document.activeElement?.tagName ?? null;"), on: page)
        XCTAssertEqual(focused["value"] as? String, "SIGN-IN-FIELD", "The component holds the focus.")

        let field = try await evaluate(.field(nil), on: page)

        XCTAssertEqual(field["error"] as? String, "unseen")
    }

    // MARK: - Fixtures

    /// What an outline answers, with its lines.
    private struct Outline {
        let title: String
        let text: String
        let truncated: Bool
        let last: String?
        let otherSites: Int

        var lines: [String] { text.split(separator: "\n").map(String.init) }

        static func isElement(_ line: String) -> Bool {
            !line.drop { $0 == " " }.hasPrefix("- text ")
        }

        /// The uid of the first element whose line contains `fragment`.
        func uid(of fragment: String) -> String? {
            guard let line = lines.first(where: { $0.contains(fragment) }),
                let range = line.range(of: #"\[uid=(e\d+)\]"#, options: .regularExpression)
            else { return nil }
            return String(line[range].dropFirst(5).dropLast())
        }
    }

    private func read(_ page: BrowserPage, _ reading: BrowserAgentPageScript.Reading = .init()) async throws
        -> Outline
    {
        let answer = try await evaluate(.snapshot(reading), on: page)
        XCTAssertNil(answer["error"])
        return Outline(
            title: answer["title"] as? String ?? "", text: answer["outline"] as? String ?? "",
            truncated: answer["truncated"] as? Bool ?? false, last: answer["last"] as? String,
            otherSites: answer["otherSites"] as? Int ?? 0)
    }

    /// What `script` answers in the agent's world of `page`, as an object;
    /// any other value is under `value`.
    private func evaluate(_ script: BrowserAgentPageScript, on page: BrowserPage) async throws -> [String: Any] {
        let settled = await page.enginePage.evaluate(script.source, in: .agent, timeout: .seconds(10))
        let evaluated = try XCTUnwrap(settled, "The script did not settle.")
        if let error = evaluated.error { XCTFail("The script threw: \(error)") }
        let value = try JSONSerialization.jsonObject(
            with: Data((evaluated.json ?? "null").utf8), options: .fragmentsAllowed)
        return value as? [String: Any] ?? ["value": value]
    }

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "OdeTestFixtures/Agents")

    /// A WebKit page showing the fixture `name`, at an https address or as
    /// `server` serves it, laid out at 1280 by 800 points as a page held for
    /// an agent is.
    private func load(_ name: String, from served: URL? = nil) async throws -> BrowserPage {
        let html = try String(contentsOf: Self.fixtures.appending(path: name), encoding: .utf8)
        let tab = TabState.Seed.startPage()
        let space = SpaceState.Seed(
            profileID: UUID(), name: "Agent Fixture", symbol: "sparkles", accent: .indigo, folders: [], tabs: [tab])
        let pool = BrowserPagePool(
            browser: .hostingPages(SessionState.Seed(spaces: [space])), usesEphemeralWebsiteDataStores: true)
        pools.append(pool)
        pool.present(tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        page.enginePage.holdRendering(true, size: CGSize(width: 1280, height: 800))
        if let served {
            page.webView.load(URLRequest(url: served))
        } else {
            page.webView.loadSimulatedRequest(
                URLRequest(url: try XCTUnwrap(URL(string: "https://fixture.ode.test/\(name)"))), responseHTML: html)
        }
        try await waitUntil("the fixture to load") {
            let state =
                try? await page.webView.evaluateJavaScript("document.readyState + ' ' + location.pathname") as? String
            return state == "complete /\(name)"
        }
        return page
    }
}
