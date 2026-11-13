import Foundation

/// Gmail's Atom feed of a signed-in inbox's unread mail, as a pinned Gmail
/// tab fetches it from its own site with its own session: the unread count,
/// the account it belongs to and the newest unread messages. The feed's
/// links name a message by its id; each item opens that message in the
/// tab's own account instead.
final class BrowserGmailFeed: NSObject, XMLParserDelegate {
    // MARK: - Types

    /// What the Gmail reader answers: the feed's HTTP status and, when the
    /// site served it, its text.
    private struct Answer: Decodable {
        let status: Int
        let feed: String?
    }

    fileprivate struct Entry {
        var title = ""
        var senderName = ""
        var senderEmail = ""
        var link: String?
        var issued: String?
        var modified: String?
        var id = ""
    }

    // MARK: - Static Variables

    /// The most feed text Ode reads; Gmail's holds twenty short entries.
    static let maximumLength = 1 << 20
    /// What the feed answers a page that is not signed in: unauthorized, or
    /// a redirect to sign in that the reader does not follow.
    static let signedOutStatuses: Set<Int> = [0, 401, 403]

    // MARK: - Variables

    private var fullCount: Int?
    private var feedTitle = ""
    private var entries: [Entry] = []
    private var entry: Entry?
    private var path: [String] = []
    private var text = ""

    // MARK: - Actions - Reading

    /// The preview the Gmail reader's `answer`, its JSON text, describes, read
    /// at `readAt`, with each message opening under `inbox`: a signed-out
    /// preview when the site refused the page's session, and nil when the
    /// reader failed or the site answered with something else.
    static func preview(answer: Data, inbox: URL, readAt: Date) -> BrowserTabPreview? {
        guard let answer = try? JSONDecoder().decode(Answer.self, from: answer) else { return nil }
        if signedOutStatuses.contains(answer.status) { return BrowserTabPreview(isSignedOut: true, readAt: readAt) }
        guard answer.status == 200, let feed = answer.feed else { return nil }
        return preview(of: feed, inbox: inbox, readAt: readAt)
    }

    /// The preview `feed` describes, read at `readAt`, with each message
    /// opening under `inbox`, the tab's inbox address such as
    /// `https://mail.google.com/mail/u/1/`. Nil for text that is not
    /// Gmail's feed.
    static func preview(of feed: String, inbox: URL, readAt: Date) -> BrowserTabPreview? {
        guard feed.utf8.count <= maximumLength else { return nil }
        let reader = BrowserGmailFeed()
        let parser = XMLParser(data: Data(feed.utf8))
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.path.isEmpty, reader.fullCount != nil || !reader.feedTitle.isEmpty else {
            return nil
        }
        let items = reader.entries.prefix(BrowserTabPreview.maximumItems).map { $0.item(inbox: inbox) }
        return BrowserTabPreview(
            account: reader.account, unreadCount: reader.fullCount ?? items.count, items: Array(items), readAt: readAt)
    }

    /// The address the feed was written for: the last word of its title that
    /// holds an at sign, as in "Gmail - Inbox for jane@example.com".
    private var account: String? {
        feedTitle.split(separator: " ").last { $0.contains("@") }.map(String.init)
    }

    // MARK: - Actions - Parsing

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        path.append(elementName)
        text = ""
        if elementName == "entry" {
            entry = Entry()
        } else if elementName == "link", entry != nil, attributes["rel"] ?? "alternate" == "alternate" {
            entry?.link = attributes["href"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = path.dropLast().last
        if var current = entry {
            switch (parent, elementName) {
            case ("entry", "title"): current.title = value
            case ("entry", "issued"): current.issued = value
            case ("entry", "modified"): current.modified = value
            case ("entry", "id"): current.id = value
            case ("author", "name"): current.senderName = value
            case ("author", "email"): current.senderEmail = value
            default: break
            }
            entry = current
            if elementName == "entry" {
                entries.append(current)
                entry = nil
            }
        } else if parent == "feed" {
            if elementName == "fullcount" { fullCount = Int(value).map { max(0, $0) } }
            if elementName == "title" { feedTitle = value }
        }
        path.removeLast()
        text = ""
    }
}

extension BrowserGmailFeed.Entry {
    // MARK: - Actions - Items

    /// The message as a preview item, opening in the inbox at `inbox`.
    fileprivate func item(inbox: URL) -> BrowserTabPreview.Item {
        let messageID = link.flatMap(URLComponents.init(string:))?.queryItems?
            .first { $0.name == "message_id" }?.value
        let id = messageID ?? id
        return BrowserTabPreview.Item(
            id: id.isEmpty ? UUID().uuidString : id,
            title: title.isEmpty
                ? String(localized: "(no subject)", comment: "A mail preview's message that has no subject.") : title,
            sender: senderName.isEmpty ? senderEmail : senderName,
            date: (issued ?? modified).flatMap { try? Date($0, strategy: .iso8601) },
            link: messageID.flatMap { messageID in
                guard messageID.allSatisfy(\.isHexDigit) else { return nil }
                return URL(string: "#inbox/\(messageID)", relativeTo: inbox)?.absoluteURL
            }
        )
    }
}
