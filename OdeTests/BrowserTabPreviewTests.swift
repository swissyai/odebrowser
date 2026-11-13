import WebKit
import XCTest

@testable import Ode

/// A pinned Gmail tab's preview comes from the feed its own page fetches: the
/// unread count, the newest messages, and links that open each one in the
/// tab's own account. Previews are read only from awake pinned or saved tabs
/// on a site the person keeps previews on for, on the site's schedule, and
/// live only in memory.
@MainActor
final class BrowserTabPreviewTests: XCTestCase {
    private let readAt = Date(timeIntervalSince1970: 1_793_556_000)  // 2026-11-01T18:00:00Z

    private var feed: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/TabPreviews/gmail-feed.xml")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    private func answer(status: Int, feed: String? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": status, "feed": feed.map { $0 as Any } ?? NSNull()])
    }

    // MARK: - Gmail's feed

    func testTheFeedGivesTheCountAccountAndNewestMessagesOpeningInTheTabsAccount() throws {
        let page = try XCTUnwrap(URL(string: "https://mail.google.com/mail/u/1/#inbox"))
        let preview = try XCTUnwrap(
            BrowserTabPreviewSite.gmail.preview(from: answer(status: 200, feed: feed), page: page, readAt: readAt))

        XCTAssertEqual(preview.unreadCount, 27)
        XCTAssertEqual(preview.account, "jane.doe@example.com")
        XCTAssertEqual(
            preview.items.map(\.title), ["Quarterly plan draft", "Lunch on Thursday & a question", "(no subject)"])
        XCTAssertEqual(preview.items.map(\.sender), ["Alex Rivera", "sam@example.org", "Example Newsletter"])
        XCTAssertEqual(preview.items[0].date, try Date("2026-11-01T17:42:00Z", strategy: .iso8601))
        XCTAssertEqual(
            preview.items[0].link?.absoluteString, "https://mail.google.com/mail/u/1/#inbox/19a2b3c4d5e6f708")
        // A link that names no message, or names one elsewhere, opens nothing.
        XCTAssertNil(preview.items[2].link)
        XCTAssertFalse(preview.isSignedOut)
    }

    func testAPageWithoutAnAccountInItsAddressReadsTheFirstAccount() throws {
        let page = try XCTUnwrap(URL(string: "https://mail.google.com/mail/?tab=rm"))
        XCTAssertEqual(
            BrowserTabPreviewSite.gmail.home(of: page)?.absoluteString, "https://mail.google.com/mail/u/0/")
    }

    func testASignedOutPageAndAnythingButTheFeedAreToldApart() throws {
        let page = try XCTUnwrap(URL(string: "https://mail.google.com/mail/u/0/"))
        for status in [0, 401, 403] {
            let preview = BrowserTabPreviewSite.gmail.preview(
                from: try answer(status: status), page: page, readAt: readAt)
            XCTAssertEqual(preview?.isSignedOut, true, "status \(status)")
            XCTAssertNil(preview?.badge(at: readAt))
        }
        XCTAssertNil(BrowserTabPreviewSite.gmail.preview(from: try answer(status: 500), page: page, readAt: readAt))
        XCTAssertNil(
            BrowserTabPreviewSite.gmail.preview(
                from: try answer(status: 200, feed: "<html><body>Sign in</body></html>"), page: page, readAt: readAt))
        XCTAssertNil(BrowserTabPreviewSite.gmail.preview(from: Data("not json".utf8), page: page, readAt: readAt))
    }

    func testOnlyGmailAndGoogleCalendarOverHTTPSHavePreviews() {
        XCTAssertEqual(BrowserTabPreviewSite.matching(URL(string: "https://mail.google.com/mail/u/0/")), .gmail)
        XCTAssertEqual(BrowserTabPreviewSite.matching(URL(string: "https://MAIL.google.com/")), .gmail)
        XCTAssertEqual(
            BrowserTabPreviewSite.matching(URL(string: "https://calendar.google.com/calendar/u/0/r")), .googleCalendar)
        XCTAssertNil(BrowserTabPreviewSite.matching(URL(string: "http://mail.google.com/mail/")))
        XCTAssertNil(BrowserTabPreviewSite.matching(URL(string: "https://mail.google.com.example.net/")))
        XCTAssertNil(BrowserTabPreviewSite.matching(URL(string: "https://www.google.com/")))
    }

    // MARK: - Google Calendar's page

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func calendarDate(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date? {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))
    }

    func testTheCalendarPageGivesItsEventsSoonestFirstWithoutDeclinedOnesOrUnreadableLabels() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/TabPreviews/calendar-week.json")
        let home = try XCTUnwrap(URL(string: "https://calendar.google.com/calendar/u/1/"))
        let preview = try XCTUnwrap(
            BrowserCalendarAgenda.preview(answer: Data(contentsOf: url), home: home, readAt: readAt, calendar: calendar)
        )

        XCTAssertEqual(preview.account, "jane.doe@example.com")
        XCTAssertNil(preview.unreadCount)
        XCTAssertEqual(
            preview.items.map(\.title),
            ["Morning check-in", "Design review", "Lunch with Sam", "Late deploy", "Team planning", "Company holiday"])
        let byTitle = Dictionary(uniqueKeysWithValues: preview.items.map { ($0.title, $0) })
        // A start without its half of the day takes the end's.
        XCTAssertEqual(byTitle["Design review"]?.date, calendarDate(3, 10))
        XCTAssertEqual(byTitle["Design review"]?.endDate, calendarDate(3, 10, 30))
        XCTAssertEqual(byTitle["Lunch with Sam"]?.date, calendarDate(3, 11, 30))
        XCTAssertEqual(byTitle["Lunch with Sam"]?.endDate, calendarDate(3, 13))
        XCTAssertEqual(byTitle["Team planning"]?.date, calendarDate(4, 16))
        // An event past midnight ends the next day.
        XCTAssertEqual(byTitle["Late deploy"]?.endDate, calendarDate(4, 1))
        // A day without a column comes from the label.
        XCTAssertEqual(byTitle["Company holiday"]?.isAllDay, true)
        XCTAssertEqual(byTitle["Company holiday"]?.date, calendarDate(5, 0))
        XCTAssertEqual(
            byTitle["Design review"]?.link?.absoluteString,
            "https://calendar.google.com/calendar/u/1/r/eventedit/ZXZlbnQy")
        // An id that is not one opens nothing.
        XCTAssertNil(byTitle["Late deploy"]?.link)
    }

    func testOnlyEventsStillToComeAreShownAndTheBadgeCountsDownWithinTheHour() throws {
        let home = try XCTUnwrap(URL(string: "https://calendar.google.com/calendar/u/0/"))
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/TabPreviews/calendar-week.json")
        let preview = try XCTUnwrap(
            BrowserCalendarAgenda.preview(answer: Data(contentsOf: url), home: home, readAt: readAt, calendar: calendar)
        )
        let beforeReview = try XCTUnwrap(calendarDate(3, 9, 48))

        XCTAssertEqual(preview.current(at: beforeReview).first?.title, "Design review")
        XCTAssertEqual(preview.badge(at: beforeReview)?.text, "12m")
        XCTAssertEqual(preview.badge(at: try XCTUnwrap(calendarDate(3, 10, 5)))?.text, "Now")
        XCTAssertNil(preview.badge(at: try XCTUnwrap(calendarDate(3, 14))), "Nothing starts within the hour.")
        XCTAssertNil(BrowserCalendarAgenda.preview(answer: Data("null".utf8), home: home, readAt: readAt))
    }

    // MARK: - Badge

    func testTheBadgeCountsRecentUnreadMailUpToItsLimit() {
        XCTAssertNil(BrowserTabPreview(unreadCount: 0, readAt: readAt).badge(at: readAt))
        XCTAssertEqual(BrowserTabPreview(unreadCount: 7, readAt: readAt).badge(at: readAt)?.text, "7")
        XCTAssertEqual(BrowserTabPreview(unreadCount: 99, readAt: readAt).badge(at: readAt)?.text, "99")
        XCTAssertEqual(BrowserTabPreview(unreadCount: 1_250, readAt: readAt).badge(at: readAt)?.text, "99+")
        XCTAssertNil(BrowserTabPreview(unreadCount: 3, isSignedOut: true, readAt: readAt).badge(at: readAt))
        // A count no read has confirmed for half an hour, as while its tab
        // sleeps, leaves the tab.
        XCTAssertEqual(BrowserTabPreview(unreadCount: 3, readAt: readAt).badge(at: readAt + 30 * 60)?.text, "3")
        XCTAssertNil(BrowserTabPreview(unreadCount: 3, readAt: readAt).badge(at: readAt + 30 * 60 + 1))
    }

    // MARK: - Schedule

    func testAReadIsDueFirstThenOnTheIntervalAndOnEachNewDocument() {
        var timing = BrowserTabPreviewTiming()
        XCTAssertTrue(timing.isDue(at: readAt, every: 120, generation: 1))

        timing.begin(at: readAt, generation: 1)
        timing.succeed(at: readAt)
        XCTAssertFalse(timing.isDue(at: readAt + 119, every: 120, generation: 1))
        XCTAssertTrue(timing.isDue(at: readAt + 120, every: 120, generation: 1))
        // The person reloaded the page: its new document is read at once.
        XCTAssertTrue(timing.isDue(at: readAt + 5, every: 120, generation: 2))
    }

    func testFailedReadsRetrySoonThenBackOffToAHalfHour() {
        var timing = BrowserTabPreviewTiming()
        var now = readAt
        var delays: [TimeInterval] = []
        for _ in 0..<10 {
            timing.begin(at: now, generation: 1)
            timing.fail()
            let next = timing.nextRead(every: 120) ?? now
            delays.append(next.timeIntervalSince(now))
            now = next
        }
        XCTAssertEqual(delays, [15, 30, 60, 120, 240, 480, 960, 1_800, 1_800, 1_800])

        timing.begin(at: now, generation: 1)
        timing.succeed(at: now)
        XCTAssertEqual(timing.nextRead(every: 120), now + 120)
    }

    func testHoveringReadsOnlyAPreviewThatIsNoLongerFresh() {
        var timing = BrowserTabPreviewTiming()
        XCTAssertFalse(timing.isFresh(at: readAt))
        timing.begin(at: readAt, generation: 1)
        timing.succeed(at: readAt)
        XCTAssertTrue(timing.isFresh(at: readAt + 29))
        XCTAssertFalse(timing.isFresh(at: readAt + 30))
    }

    // MARK: - Center

    func testOnlyAwakePinnedTabsOnSitesWithPreviewsOnAreReadAndOnlyInMemory() async throws {
        let gmail = try XCTUnwrap(URL(string: "https://mail.google.com/mail/u/0/#inbox"))
        let other = try XCTUnwrap(URL(string: "https://example.com/"))
        let awake = UUID()
        let asleep = UUID()
        let elsewhere = UUID()
        var reads: [String] = []
        let feed = try feed
        let answer = String(decoding: try answer(status: 200, feed: feed), as: UTF8.self)
        let document = BrowserTabPreviewDocument { body, _ in
            reads.append(body)
            return answer
        }
        var sources = [
            BrowserTabPreviewCenter.Source(tabID: awake, url: gmail, document: document, generation: 1),
            BrowserTabPreviewCenter.Source(tabID: asleep, url: gmail, document: nil, generation: 0),
            BrowserTabPreviewCenter.Source(tabID: elsewhere, url: other, document: document, generation: 1),
        ]
        var preferences = TabPreviewPreferences.default
        var now = readAt
        let center = BrowserTabPreviewCenter()
        center.sources = { sources }
        center.preferences = { preferences }
        center.now = { now }

        center.refresh()
        try await waitUntil(interval: .milliseconds(10)) { center.previews[awake] != nil }
        XCTAssertEqual(reads.count, 1, "Only the awake Gmail tab is read.")
        XCTAssertEqual(center.preview(of: awake, at: gmail)?.unreadCount, 27)
        XCTAssertNil(center.previews[asleep])
        XCTAssertNil(center.previews[elsewhere])

        // Not due again until the site's interval passes.
        now += 60
        center.refresh()
        XCTAssertEqual(reads.count, 1)

        // While the system is short of memory, nothing is read.
        center.relieveMemoryPressure(.warning)
        now += 120
        center.refresh()
        XCTAssertEqual(reads.count, 1)

        // The tab falls asleep: it keeps its last preview and is not read.
        sources[0] = BrowserTabPreviewCenter.Source(tabID: awake, url: gmail, document: nil, generation: 1)
        now += 3_600
        center.refresh()
        XCTAssertEqual(reads.count, 1)
        XCTAssertNotNil(center.previews[awake])

        // Turning the site's previews off hides the preview at once and
        // forgets it at the next look.
        preferences = preferences.settingPreviews(false, on: "mail.google.com")
        XCTAssertNil(center.preview(of: awake, at: gmail))
        center.refresh()
        XCTAssertTrue(center.previews.isEmpty)

        // A tab that leaves the pinned and saved tabs loses its preview.
        preferences = .default
        sources[0] = BrowserTabPreviewCenter.Source(tabID: awake, url: gmail, document: document, generation: 2)
        center.refresh()
        try await waitUntil(interval: .milliseconds(10)) { center.previews[awake] != nil }
        sources.removeFirst()
        center.refresh()
        XCTAssertNil(center.previews[awake])
    }

    // MARK: - WebKit

    func testTheGmailReaderAsksOnlyThePagesOwnSiteWithThePagesOwnSession() async throws {
        let feed = try feed
        let server = try BrowserPrivacyHTTPServer()
        server.overrideResponse = { request in
            if request.path == "/mail/u/0/feed/atom" {
                guard request.headers["cookie"]?.contains("session=fixture") == true else {
                    return ("401 Unauthorized", "WWW-Authenticate: Basic realm=\"Fixture\"\r\n", Data())
                }
                return ("200 OK", "Content-Type: application/atom+xml\r\n", Data(feed.utf8))
            }
            let cookie = request.query == "signed-in" ? "Set-Cookie: session=fixture; Path=/; HttpOnly\r\n" : ""
            return ("200 OK", "Content-Type: text/html\r\n\(cookie)", Data("<html><body>Inbox</body></html>".utf8))
        }
        try await server.start()
        defer { server.stop() }

        for (query, isSignedIn) in [("signed-in", true), ("signed-out", false)] {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            let page = server.url(host: "127.0.0.1", path: "/mail/u/0/?\(query)")
            webView.load(URLRequest(url: page))
            try await waitUntil(interval: .milliseconds(10)) { !webView.isLoading && webView.url != nil }

            let answer = await BrowserTabPreviewDocument(webView: webView)
                .read(BrowserTabPreviewSite.gmail.reader, timeout: .seconds(10))
            let preview = try XCTUnwrap(
                answer.flatMap { BrowserTabPreviewSite.gmail.preview(from: $0, page: page, readAt: readAt) })
            XCTAssertEqual(preview.isSignedOut, !isSignedIn)
            XCTAssertEqual(preview.unreadCount, isSignedIn ? 27 : nil)
            // The reader leaves nothing the page's own scripts can see.
            let pageGlobals = try await webView.evaluateJavaScript("Object.keys(window).join(',')") as? String
            XCTAssertFalse(pageGlobals?.contains("account") ?? true)
        }
        let feedRequests = server.requests.filter { $0.path == "/mail/u/0/feed/atom" }
        XCTAssertTrue(feedRequests.contains { $0.headers["cookie"]?.contains("session=fixture") == true })
        XCTAssertTrue(feedRequests.allSatisfy { $0.host == "127.0.0.1:\(server.port)" })
        XCTAssertTrue(server.requests.allSatisfy { $0.path.hasPrefix("/mail/u/0/") })
    }
}
