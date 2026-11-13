import Foundation

// MARK: - Types

/// An icon found for a page: the bytes a tab wears, where they came from, what
/// the site called the icon and the image's size in pixels.
struct BrowserSiteIconFinding: Sendable {
    let image: BrowserSiteIconImage
    let iconURL: URL
    let relation: BrowserSiteIconRelation

    var data: Data { image.data }
}

/// Which pages of one profile share an icon: those of one site under one
/// first path segment, such as a document app and a spreadsheet app on the
/// same host.
struct BrowserSiteIconKey: Hashable, Sendable {
    let profileID: UUID
    let scope: String
}

/// A lookup that found nothing, and when its pages may be asked again.
private struct BrowserSiteIconMiss {
    let retryAt: ContinuousClock.Instant
    let attempts: Int
}

private struct BrowserSiteIconLease {
    let generation: UInt64
    let task: Task<BrowserSiteIconLookup, Never>
}

/// What a lookup came to: an icon, an answer from the site with none, or no
/// answer from the site at all.
private enum BrowserSiteIconLookup: Sendable {
    case found(BrowserSiteIconFinding)
    case missing
    case unreachable
}

/// Finds the icon of a page no tab has loaded, the way the page itself would
/// show one: it reads the page's head for the icons it declares and the web
/// app manifest it links, and picks the one that suits a tab best, else the
/// site's `/favicon.ico`.
///
/// Every request goes through the public resource loader: no cookies, no
/// credentials, no referrer, on every redirect. The page is asked for without
/// its query or fragment, where one-time tokens live. Lookups run a few at a
/// time; a lookup that found nothing is not repeated until a retry time that
/// grows with each miss, and a site that gave no answer is asked again soon.
actor BrowserSiteIconFinder {
    // MARK: - Static Variables

    static let shared = BrowserSiteIconFinder()
    static let maximumConcurrentLookups = 3
    private static let maximumDocumentByteCount = 1_024 * 1_024
    private static let maximumManifestByteCount = 256 * 1_024
    private static let maximumIconByteCount = 512 * 1_024
    private static let maximumIconDownloads = 6
    private static let maximumCachedByteCount = 8 * 1_024 * 1_024
    private static let maximumMissCount = 512
    /// The side SVG icons are drawn at, twice the largest tile in pixels.
    private static let drawnSide = 128
    /// How long a lookup that found nothing waits before each next attempt.
    private static let missRetryDelays: [Duration] = [
        .seconds(15 * 60), .seconds(60 * 60), .seconds(6 * 60 * 60), .seconds(24 * 60 * 60),
    ]
    /// How long a site that gave no answer waits before it is asked again.
    private static let unreachableRetryDelay: Duration = .seconds(2 * 60)
    /// The labels countries register sites under, as in `co.uk`.
    private static let secondLevelLabels: Set<Substring> = ["co", "com", "net", "org", "gov", "edu", "ac", "ne", "or"]
    /// What the lookup says it is: Safari on this Mac, as Ode's pages do, so
    /// a site answers with the page a browser gets.
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
        + (BrowserPlatformUserAgent.applicationName ?? "Version/26.0 Safari/605.1.15")

    // MARK: - Variables

    private let session: URLSession?
    private let drawSVG: @Sendable (Data, Int, String?) async -> Data?
    private var found: [BrowserSiteIconKey: BrowserSiteIconFinding] = [:]
    private var foundRecency: [BrowserSiteIconKey] = []
    private var foundByteCount = 0
    private var misses: [BrowserSiteIconKey: BrowserSiteIconMiss] = [:]
    private var inFlight: [BrowserSiteIconKey: BrowserSiteIconLease] = [:]
    private var generations: [UUID: UInt64] = [:]
    private var runningCount = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initializers

    /// A finder that loads through `session`, the public resource loader's
    /// own unless a test names another, and draws SVG icons with `drawSVG`.
    init(
        session: URLSession? = nil,
        drawSVG: @escaping @Sendable (Data, Int, String?) async -> Data? = { svg, side, tint in
            await BrowserFaviconSVGRasterizer.png(from: svg, pixelSize: side, tint: tint)
        }
    ) {
        self.session = session
        self.drawSVG = drawSVG
    }

    // MARK: - Actions - Finding

    /// The icon of the page at `pageURL` for the profile `profileID`, or nil
    /// when the site offers none, or none yet that can be read.
    func icon(for pageURL: URL, profileID: UUID) async -> BrowserSiteIconFinding? {
        guard !Task.isCancelled, let document = Self.documentURL(for: pageURL) else { return nil }
        let key = BrowserSiteIconKey(profileID: profileID, scope: Self.scope(of: document))
        if let finding = found[key] {
            recordAccess(to: key)
            return finding
        }
        if let miss = misses[key], miss.retryAt > .now { return nil }

        let generation = generations[profileID, default: 0]
        let lease: BrowserSiteIconLease
        if let pending = inFlight[key], pending.generation == generation {
            lease = pending
        } else {
            let task = Task<BrowserSiteIconLookup, Never>(priority: .utility) {
                await self.runLookup(document)
            }
            lease = BrowserSiteIconLease(generation: generation, task: task)
            inFlight[key] = lease
        }
        let lookup = await lease.task.value
        guard lease.generation == generations[profileID, default: 0] else { return nil }
        if inFlight[key]?.task == lease.task {
            inFlight[key] = nil
            record(lookup, for: key)
        }
        guard case .found(let finding) = lookup else { return nil }
        return finding
    }

    /// Forgets every icon and miss of `profileID`, and stops its lookups, as a
    /// Space whose data goes must.
    func removeAll(for profileID: UUID) {
        generations[profileID, default: 0] &+= 1
        for key in found.keys where key.profileID == profileID {
            foundByteCount -= found.removeValue(forKey: key)?.data.count ?? 0
        }
        foundRecency.removeAll { $0.profileID == profileID }
        misses = misses.filter { $0.key.profileID != profileID }
        for key in inFlight.keys where key.profileID == profileID {
            inFlight.removeValue(forKey: key)?.task.cancel()
        }
    }

    private func runLookup(_ document: URL) async -> BrowserSiteIconLookup {
        await acquireSlot()
        defer { releaseSlot() }
        guard !Task.isCancelled else { return .unreachable }
        return await lookUp(document)
    }

    /// Reads the page's head, then tries its icons best first: an icon large
    /// enough ends the search, else the largest seen is kept. A page that
    /// moved to another host of its site, such as its product page or its
    /// sign-in there, keeps what that page declares, but the site-wide
    /// `/favicon.ico` of where it landed is tried only after its own. A page
    /// that moved to another site, such as a sign-in elsewhere, describes
    /// that site: its icons are tried only when the page's own
    /// `/favicon.ico` gives nothing.
    private func lookUp(_ document: URL) async -> BrowserSiteIconLookup {
        var answered = false
        var own: [BrowserSiteIconCandidate] = []
        var foreign: [BrowserSiteIconCandidate] = []
        let ownDefault = Self.defaultIcon(for: document)
        switch await BrowserFaviconResourceLoader.fetchHead(
            document, maximumByteCount: Self.maximumDocumentByteCount, userAgent: Self.userAgent, session: session)
        {
        case .resource(let page):
            answered = true
            let head = BrowserSiteIconDocument(html: page.data, url: page.url)
            var declared = head.icons
            if !declared.contains(where: \.isDeclaredLarge), let manifestURL = head.manifestURLs.first {
                declared += await manifestIcons(at: manifestURL)
            }
            let finalDefault = Self.defaultIcon(for: page.url)
            if Self.bareHost(of: page.url) == Self.bareHost(of: document) {
                own = declared + [ownDefault, finalDefault].compactMap { $0 }
            } else if Self.siteDomain(of: page.url) == Self.siteDomain(of: document) {
                own = declared + [ownDefault].compactMap { $0 }
                foreign = [finalDefault].compactMap { $0 }
            } else {
                own = [ownDefault].compactMap { $0 }
                foreign = declared + [finalDefault].compactMap { $0 }
            }
        case .refused:
            answered = true
            own = [ownDefault].compactMap { $0 }
        case .unreachable:
            own = [ownDefault].compactMap { $0 }
        }
        var budget = Self.maximumIconDownloads
        for group in [own, foreign] where !group.isEmpty {
            let (finding, reached) = await best(of: group, budget: &budget)
            answered = answered || reached
            if let finding { return .found(finding) }
        }
        return answered ? .missing : .unreachable
    }

    /// The best icon of `candidates`, tried in their order until one is
    /// large enough or `budget` downloads are spent, and whether any site
    /// answered.
    private func best(
        of candidates: [BrowserSiteIconCandidate], budget: inout Int
    ) async -> (BrowserSiteIconFinding?, Bool) {
        var tried: Set<URL> = []
        var reached = false
        var best: BrowserSiteIconFinding?
        let ordered = candidates.sorted { $0.precedes($1) }
        for candidate in ordered where budget > 0 && tried.insert(candidate.url).inserted {
            guard !Task.isCancelled else { break }
            let (image, answered) = await image(of: candidate, budget: &budget)
            reached = reached || answered
            guard let image else { continue }
            let finding = BrowserSiteIconFinding(image: image, iconURL: candidate.url, relation: candidate.relation)
            if image.isLarge { return (finding, true) }
            if best.map({ image.side > $0.image.side }) ?? true { best = finding }
        }
        return (best, reached)
    }

    /// The image `candidate` names, drawn when it is an SVG, and whether its
    /// site answered.
    private func image(
        of candidate: BrowserSiteIconCandidate, budget: inout Int
    ) async -> (BrowserSiteIconImage?, Bool) {
        let data: Data
        let mimeType: String?
        if let inline = Self.inlineData(candidate.url) {
            (data, mimeType) = inline
        } else {
            budget -= 1
            switch await BrowserFaviconResourceLoader.fetch(
                candidate.url, maximumByteCount: Self.maximumIconByteCount,
                accept: BrowserFaviconResourceLoader.iconAccept, userAgent: Self.userAgent, session: session)
            {
            case .resource(let resource):
                (data, mimeType) = (resource.data, resource.mimeType)
            case .refused:
                return (nil, true)
            case .unreachable:
                return (nil, false)
            }
        }
        if Self.isSVG(data, mimeType: mimeType) {
            guard let png = await drawSVG(data, Self.drawnSide, candidate.tint) else { return (nil, true) }
            return (BrowserSiteIconImage(raster: png), true)
        }
        return (BrowserSiteIconImage(raster: data), true)
    }

    private func manifestIcons(at url: URL) async -> [BrowserSiteIconCandidate] {
        guard
            let manifest = await BrowserFaviconResourceLoader.fetch(
                url, maximumByteCount: Self.maximumManifestByteCount,
                accept: BrowserFaviconResourceLoader.manifestAccept, userAgent: Self.userAgent, session: session
            ).resource
        else { return [] }
        return BrowserSiteIconManifest.candidates(in: manifest.data, url: manifest.url)
    }

    // MARK: - Actions - Remembering

    private func record(_ lookup: BrowserSiteIconLookup, for key: BrowserSiteIconKey) {
        switch lookup {
        case .found(let finding):
            misses[key] = nil
            insert(finding, for: key)
        case .missing:
            let attempts = (misses[key]?.attempts ?? 0) + 1
            let delay = Self.missRetryDelays[min(attempts, Self.missRetryDelays.count) - 1]
            remember(BrowserSiteIconMiss(retryAt: .now + delay, attempts: attempts), for: key)
        case .unreachable:
            let attempts = misses[key]?.attempts ?? 0
            remember(BrowserSiteIconMiss(retryAt: .now + Self.unreachableRetryDelay, attempts: attempts), for: key)
        }
    }

    private func remember(_ miss: BrowserSiteIconMiss, for key: BrowserSiteIconKey) {
        if misses[key] == nil, misses.count >= Self.maximumMissCount,
            let soonest = misses.min(by: { $0.value.retryAt < $1.value.retryAt })?.key
        {
            misses[soonest] = nil
        }
        misses[key] = miss
    }

    private func insert(_ finding: BrowserSiteIconFinding, for key: BrowserSiteIconKey) {
        foundByteCount -= found.updateValue(finding, forKey: key)?.data.count ?? 0
        foundByteCount += finding.data.count
        recordAccess(to: key)
        while foundByteCount > Self.maximumCachedByteCount, let leastRecent = foundRecency.first {
            foundRecency.removeFirst()
            foundByteCount -= found.removeValue(forKey: leastRecent)?.data.count ?? 0
        }
    }

    private func recordAccess(to key: BrowserSiteIconKey) {
        foundRecency.removeAll { $0 == key }
        foundRecency.append(key)
    }

    // MARK: - Actions - Pacing

    private func acquireSlot() async {
        if runningCount < Self.maximumConcurrentLookups {
            runningCount += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the slot to the lookup that waited longest, or frees it.
    private func releaseSlot() {
        if waiting.isEmpty {
            runningCount -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }

    // MARK: - Actions - Addresses

    /// The page `pageURL` names as it is asked for: a web address without
    /// credentials, query or fragment.
    static func documentURL(for pageURL: URL) -> URL? {
        guard ["http", "https"].contains(pageURL.scheme?.lowercased()),
            var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: true),
            components.host?.isEmpty == false
        else { return nil }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }

    /// The pages that share `document`'s icon: its site and first path
    /// segment.
    private static func scope(of document: URL) -> String {
        let host = document.host()?.lowercased() ?? ""
        let port = document.port.map { ":\($0)" } ?? ""
        let segment = document.pathComponents.dropFirst().first ?? ""
        return "\(document.scheme?.lowercased() ?? "")://\(host)\(port)/\(segment)"
    }

    private static func defaultIcon(for page: URL) -> BrowserSiteIconCandidate? {
        guard let scheme = page.scheme, let host = page.host(),
            let url = URL(string: "\(scheme)://\(host)\(page.port.map { ":\($0)" } ?? "")/favicon.ico")
        else { return nil }
        return BrowserSiteIconCandidate(url: url, relation: .defaultIcon, order: .max)
    }

    /// `url`'s host without a leading `www.`.
    private static func bareHost(of url: URL) -> String {
        let host = url.host()?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The part of `url`'s host its site registers, near enough: the last two
    /// labels, or three under a country's second-level domain such as
    /// `co.uk`.
    private static func siteDomain(of url: URL) -> String {
        let labels = (url.host()?.lowercased() ?? "").split(separator: ".")
        let isCountrySecondLevel =
            labels.count >= 3 && labels.last?.count == 2 && secondLevelLabels.contains(labels[labels.count - 2])
        return labels.suffix(isCountrySecondLevel ? 3 : 2).joined(separator: ".")
    }

    // MARK: - Actions - Contents

    /// The bytes and type of a base64 `data:` image URL.
    private static func inlineData(_ url: URL) -> (Data, String?)? {
        let value = url.absoluteString
        guard value.lowercased().hasPrefix("data:image/"), let comma = value.firstIndex(of: ",") else {
            return nil
        }
        let metadata = value[value.index(value.startIndex, offsetBy: 5)..<comma].lowercased()
        guard metadata.hasSuffix(";base64"),
            let data = Data(base64Encoded: String(value[value.index(after: comma)...])),
            !data.isEmpty, data.count <= maximumIconByteCount
        else { return nil }
        return (data, metadata.split(separator: ";").first.map(String.init))
    }

    private static func isSVG(_ data: Data, mimeType: String?) -> Bool {
        if mimeType == "image/svg+xml" { return true }
        let prefix = String(decoding: data.prefix(2_048), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
            .lowercased()
        return prefix.hasPrefix("<svg") || (prefix.hasPrefix("<?xml") && prefix.contains("<svg"))
    }
}
