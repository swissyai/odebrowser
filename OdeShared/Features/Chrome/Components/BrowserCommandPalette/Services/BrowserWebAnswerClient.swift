import Foundation

/// Fetches the Wikipedia summary a web answer card shows, from the addresses
/// the core names: the title search, the article's summary, and, for a
/// Commons picture, its author and licence and the picture itself. It sends
/// no cookies, keeps no cache and names Ode and its site in its User-Agent,
/// as Wikimedia asks of clients. A title that is not the topic stops it
/// before the summary is asked for.
actor BrowserWebAnswerClient {
    // MARK: - Static Variables

    static let shared = BrowserWebAnswerClient()

    /// The most a response may hold.
    static let maximumResponseByteCount = 512 * 1_024

    nonisolated static var sessionConfiguration: URLSessionConfiguration {
        let configuration = BrowserSearchSuggestionClient.sessionConfiguration
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent, "Api-User-Agent": userAgent]
        return configuration
    }

    /// Ode, its version and its site, as Wikimedia's policy for clients asks.
    nonisolated static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let product = ProductIdentity.name.replacingOccurrences(of: " ", with: "")
        return "\(product)/\(version) (https://odebrowser.com)"
    }

    // MARK: - Variables

    private let session: URLSession

    // MARK: - Initializers

    init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: Self.sessionConfiguration)
    }

    // MARK: - Actions - Fetching

    /// The summary of the article whose title is `lookup.topic`, with its
    /// picture's author and licence when Commons holds it, or nil.
    func summary(for lookup: PaletteWebLookup) async -> PaletteWebSummary? {
        guard let search = URL(string: lookup.searchAddress), let found = await json(search),
            let page = (found["pages"] as? [[String: Any]])?.first, let key = page["key"] as? String,
            let title = page["title"] as? String, Self.folded(title) == Self.folded(lookup.topic),
            let summaryURL = Self.filled(lookup.summaryTemplate, with: key), let summary = await json(summaryURL),
            let type = summary["type"] as? String, let extract = summary["extract"] as? String,
            let address = ((summary["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"]
                as? String
        else { return nil }
        let thumbnail = (summary["thumbnail"] as? [String: Any])?["source"] as? String
        var artist: String?
        var license: String?
        if let thumbnail, let file = Self.commonsFile(thumbnail),
            let infoURL = Self.filled(lookup.imageInfoTemplate, with: file), let info = await json(infoURL),
            let metadata =
                ((((info["query"] as? [String: Any])?["pages"] as? [[String: Any]])?.first?["imageinfo"]
                as? [[String: Any]])?.first?["extmetadata"]) as? [String: Any]
        {
            artist = ((metadata["Artist"] as? [String: Any])?["value"] as? String).map(Self.plainText)
            license = (metadata["LicenseShortName"] as? [String: Any])?["value"] as? String
            if artist != nil, license != nil, let imageURL = URL(string: thumbnail), let data = await bytes(imageURL) {
                await MainActor.run { _ = BrowserCommandPaletteCardImages.shared.keep(data, for: thumbnail) }
            }
        }
        return PaletteWebSummary(
            title: summary["title"] as? String ?? title, type: type, description: summary["description"] as? String,
            extract: extract, page: address, thumbnail: thumbnail, imageArtist: artist, imageLicense: license)
    }

    private func json(_ address: URL) async -> [String: Any]? {
        guard let data = await bytes(address, accept: "application/json") else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func bytes(_ address: URL, accept: String? = nil) async -> Data? {
        guard let routed = BrowserNetworkFixture.routed(address) else { return nil }
        let delegate = routed == address ? nil : BrowserNetworkFixture.redirectGuard
        var request = URLRequest(url: routed)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        guard let (data, response) = try? await session.data(for: request, delegate: delegate),
            let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
            data.count <= Self.maximumResponseByteCount
        else { return nil }
        return data
    }

    // MARK: - Actions - Reading

    /// `template` with `%s` replaced by `value`, encoded as one path or
    /// query part.
    static func filled(_ template: String, with value: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?&=+#")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }

    /// The name of the Commons file a picture address shows, or nil for a
    /// picture Commons does not hold.
    static func commonsFile(_ address: String) -> String? {
        guard let url = URL(string: address), url.path.contains("/wikipedia/commons/") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let commons = parts.firstIndex(of: "commons") else { return nil }
        let name = parts.count > commons + 1 && parts[commons + 1] == "thumb" ? commons + 4 : commons + 3
        return parts.indices.contains(name) ? parts[name].removingPercentEncoding : nil
    }

    /// `html` as plain text, as Commons writes an author.
    static func plainText(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'").replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func folded(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: nil
        )
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
