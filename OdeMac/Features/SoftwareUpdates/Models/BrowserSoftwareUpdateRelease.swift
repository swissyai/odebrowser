import Foundation

/// A release the update feed lists, as Ode reads it to offer going back to
/// an earlier version: its versions, when it was published, the macOS it
/// needs, its channel, and the disk image with its EdDSA signature.
struct BrowserSoftwareUpdateRelease: Equatable, Identifiable, Sendable {
    // MARK: - Variables

    /// The marketing version, such as 0.8.79.
    let version: String
    /// The build number (`CFBundleVersion`), which orders releases.
    let build: String
    let publishedAt: Date?
    let archive: URL
    let length: Int64
    /// The base64 EdDSA signature of the disk image.
    let signature: String
    let minimumSystemVersion: String?
    /// The Sparkle channel, or nil for the default channel every Ode follows.
    let channel: String?

    var id: String { build }

    // MARK: - Actions - Reading

    /// The releases `feed` lists, in its order. An item without a full
    /// download, its length or its signature is left out: Ode never installs
    /// what it cannot verify.
    static func releases(inFeed feed: Data) -> [Self] {
        let reader = BrowserSoftwareUpdateFeedReader()
        let parser = XMLParser(data: feed)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { return [] }
        return reader.releases
    }

    // MARK: - Actions - Choosing

    /// Whether this release is an earlier build than `build`.
    func isOlder(thanBuild build: String) -> Bool {
        self.build.compare(build, options: .numeric) == .orderedAscending
    }

    /// Whether this release runs on macOS `system`.
    func runs(on system: OperatingSystemVersion) -> Bool {
        guard let minimumSystemVersion else { return true }
        let running = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
        return minimumSystemVersion.compare(running, options: .numeric) != .orderedDescending
    }

    /// Whether a person following `allowedChannels`, beyond the default
    /// channel, may install this release.
    func belongs(to allowedChannels: Set<String>) -> Bool {
        channel.map(allowedChannels.contains) ?? true
    }
}

/// Reads an appcast's items: only full downloads, never the deltas beside
/// them, which need the version they patch.
private final class BrowserSoftwareUpdateFeedReader: NSObject, XMLParserDelegate {
    // MARK: - Types

    private struct Item {
        var version: String?
        var build: String?
        var publishedAt: String?
        var minimumSystemVersion: String?
        var channel: String?
        var archive: URL?
        var length: Int64?
        var signature: String?
    }

    // MARK: - Variables

    private(set) var releases: [BrowserSoftwareUpdateRelease] = []
    /// Feeds date their items as RSS does.
    private let dates: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
    private var item: Item?
    private var inDeltas = false
    private var text = ""

    // MARK: - Actions - Parsing

    func parser(
        _ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        text = ""
        switch element {
        case "item":
            item = Item()
        case "sparkle:deltas":
            inDeltas = true
        case "enclosure" where !inDeltas:
            guard var current = item else { break }
            current.archive = attributes["url"].flatMap(URL.init(string:))
            current.length = attributes["length"].flatMap { Int64($0) }
            current.signature = attributes["sparkle:edSignature"]
            // Sparkle 1 feeds put the versions on the enclosure.
            if current.build == nil { current.build = attributes["sparkle:version"] }
            if current.version == nil { current.version = attributes["sparkle:shortVersionString"] }
            item = current
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        switch element {
        case "sparkle:deltas":
            inDeltas = false
        case "sparkle:version" where item != nil:
            item?.build = value
        case "sparkle:shortVersionString" where item != nil:
            item?.version = value
        case "pubDate" where item != nil:
            item?.publishedAt = value
        case "sparkle:minimumSystemVersion" where item != nil:
            item?.minimumSystemVersion = value
        case "sparkle:channel" where item != nil:
            item?.channel = value
        case "item":
            if let item, let build = item.build, let archive = item.archive, let length = item.length,
                let signature = item.signature, archive.scheme == "https" || archive.scheme == "http"
            {
                releases.append(
                    BrowserSoftwareUpdateRelease(
                        version: item.version ?? build, build: build,
                        publishedAt: item.publishedAt.flatMap(dates.date(from:)), archive: archive,
                        length: length, signature: signature, minimumSystemVersion: item.minimumSystemVersion,
                        channel: item.channel))
            }
            item = nil
        default:
            break
        }
    }
}
