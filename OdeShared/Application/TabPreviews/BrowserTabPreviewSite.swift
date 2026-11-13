import Foundation

/// A site whose pinned and saved tabs show a preview on hover, with the
/// reader that runs in the tab's own page to learn what the site holds for
/// the person, and how often it runs. A reader asks only the site itself,
/// with the page's own session; Ode never sees a password or a token.
struct BrowserTabPreviewSite: Sendable {
    // MARK: - Types

    /// The preview a reader's answer, its JSON text, describes for the page
    /// whose account home is the given address, read at the given time.
    typealias Decode = @Sendable (_ answer: Data, _ home: URL, _ readAt: Date) -> BrowserTabPreview?

    // MARK: - Static Variables

    /// Gmail's unread mail, from the feed Gmail serves a signed-in page.
    static let gmail = BrowserTabPreviewSite(
        name: "gmail", title: "Gmail", emptyText: "No unread mail", host: "mail.google.com", accountPath: "/mail/u/",
        refreshInterval: 2 * 60, reader: gmailReader,
        decode: { answer, home, readAt in BrowserGmailFeed.preview(answer: answer, inbox: home, readAt: readAt) })

    /// Google Calendar's next events, from the calendar page the tab shows.
    static let googleCalendar = BrowserTabPreviewSite(
        name: "googleCalendar", title: "Google Calendar", emptyText: "No more events", host: "calendar.google.com",
        accountPath: "/calendar/u/", refreshInterval: 3 * 60, reader: calendarReader,
        decode: { answer, home, readAt in BrowserCalendarAgenda.preview(answer: answer, home: home, readAt: readAt) })

    static let all: [BrowserTabPreviewSite] = [gmail, googleCalendar]

    // MARK: - Variables

    /// The site's stable name, which a fixture names it by.
    let name: String
    /// What Settings and the site's preview call the site.
    let title: LocalizedStringResource
    /// What the site's preview says when it holds nothing.
    let emptyText: LocalizedStringResource
    /// The host of the site's pages.
    let host: String
    /// Where the site's paths name the signed-in account, as `/mail/u/1/`
    /// names a second Google account.
    let accountPath: String
    /// How long a preview lasts before its tab is read again.
    let refreshInterval: TimeInterval
    /// The script that reads the page: the body of an async function, run in
    /// Ode's own script world, that returns its answer as JSON text.
    let reader: String
    private let decode: Decode

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, emptyText: LocalizedStringResource, host: String,
        accountPath: String, refreshInterval: TimeInterval, reader: String, decode: @escaping Decode
    ) {
        self.name = name
        self.title = title
        self.emptyText = emptyText
        self.host = host
        self.accountPath = accountPath
        self.refreshInterval = refreshInterval
        self.reader = reader
        self.decode = decode
    }

    // MARK: - Actions - Lookup

    /// The site whose pages `url` shows over HTTPS, if one has previews.
    static func matching(_ url: URL?) -> BrowserTabPreviewSite? {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host(percentEncoded: false)?.lowercased()
        else { return nil }
        return all.first { $0.host == host }
    }

    static func named(_ name: String?) -> BrowserTabPreviewSite? {
        all.first { $0.name == name }
    }

    // MARK: - Actions - Reading

    /// The account home of the page at `url`: its origin and the account
    /// path with the account the page shows, the first one when it names
    /// none, as in `https://mail.google.com/mail/u/1/`.
    func home(of url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let rest = components.path.hasPrefix(accountPath) ? components.path.dropFirst(accountPath.count) : ""
        let account = rest.prefix { $0.isASCII && $0.isNumber }
        components.path = accountPath + (account.isEmpty ? "0" : account) + "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// The preview the reader's `answer` describes for the page at `url`.
    func preview(from answer: Data, page url: URL, readAt: Date) -> BrowserTabPreview? {
        home(of: url).flatMap { decode(answer, $0, readAt) }
    }
}

extension BrowserTabPreviewSite: Hashable {
    static func == (lhs: BrowserTabPreviewSite, rhs: BrowserTabPreviewSite) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
