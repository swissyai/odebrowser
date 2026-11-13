import Foundation

/// Native loading is only a public-resource fallback. Authenticated resources
/// belong to the live page's WebKit context, never an exported cookie snapshot.
enum BrowserFaviconResourceLoader {
    struct Resource: Sendable {
        let data: Data
        let mimeType: String?
        let url: URL

        var isImage: Bool {
            mimeType?.hasPrefix("image/") == true || mimeType == "application/octet-stream"
        }
    }

    /// What one fetch came to: a resource, an answer that holds none Ode can
    /// use, or no answer at all, such as while the Mac is offline.
    enum Outcome: Sendable {
        case resource(Resource)
        case refused
        case unreachable

        var resource: Resource? {
            guard case .resource(let resource) = self else { return nil }
            return resource
        }
    }

    static let iconAccept = "image/avif,image/webp,image/png,image/svg+xml,image/*,*/*;q=0.5"
    static let manifestAccept = "application/manifest+json,application/json,*/*;q=0.5"
    static let documentAccept = "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5"
    private static let headEnd = Array("</head>".utf8)

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }()

    static func download(
        _ url: URL,
        maximumByteCount: Int,
        accept: String,
        userAgent: String? = nil,
        session requestedSession: URLSession? = nil
    ) async -> Resource? {
        await fetch(
            url, maximumByteCount: maximumByteCount, accept: accept, userAgent: userAgent, session: requestedSession
        ).resource
    }

    /// The resource at `url`, whole, when a successful answer carries at most
    /// `maximumByteCount` bytes.
    static func fetch(
        _ url: URL,
        maximumByteCount: Int,
        accept: String,
        userAgent: String? = nil,
        session requestedSession: URLSession? = nil
    ) async -> Outcome {
        await load(
            url, maximumByteCount: maximumByteCount, accept: accept, userAgent: userAgent,
            session: requestedSession, readsHead: false)
    }

    /// The HTML of the page at `url` up to the end of its head, or its first
    /// `maximumByteCount` bytes. A page that answers with a client error is
    /// read too, since it carries the site's head like any other.
    static func fetchHead(
        _ url: URL,
        maximumByteCount: Int,
        userAgent: String? = nil,
        session requestedSession: URLSession? = nil
    ) async -> Outcome {
        await load(
            url, maximumByteCount: maximumByteCount, accept: documentAccept, userAgent: userAgent,
            session: requestedSession, readsHead: true)
    }

    private static func load(
        _ url: URL,
        maximumByteCount: Int,
        accept: String,
        userAgent: String?,
        session requestedSession: URLSession?,
        readsHead: Bool
    ) async -> Outcome {
        guard let url = publicResourceURL(url) else { return .refused }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 12
        )
        request.httpShouldHandleCookies = false
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let userAgent, !userAgent.isEmpty, userAgent.utf8.count <= 1_024,
            !userAgent.contains("\r"), !userAgent.contains("\n")
        {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        do {
            let (bytes, response) = try await (requestedSession ?? session).bytes(
                for: request, delegate: PublicResourceDelegate()
            )
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse,
                (readsHead ? 200..<500 : 200..<300).contains(response.statusCode),
                readsHead ? isDocument(response.mimeType) : response.expectedContentLength <= maximumByteCount,
                let responseURL = response.url
            else {
                // A response rejected before iteration can leave AsyncBytes'
                // task retained in its session. Finish its response callback
                // in an independent cancellation scope, even if the page left.
                let cleanup = Task {
                    bytes.task.cancel()
                    var iterator = bytes.makeAsyncIterator()
                    _ = try? await iterator.next()
                }
                await cleanup.value
                return .refused
            }
            var data = Data()
            for try await byte in bytes {
                guard !Task.isCancelled else { return .unreachable }
                guard data.count < maximumByteCount else {
                    if readsHead { break }
                    return .refused
                }
                data.append(byte)
                if readsHead, byte == UInt8(ascii: ">"), endsHead(data) { break }
            }
            guard !data.isEmpty else { return .refused }
            return .resource(Resource(data: data, mimeType: response.mimeType?.lowercased(), url: responseURL))
        } catch {
            return .unreachable
        }
    }

    private static func isDocument(_ mimeType: String?) -> Bool {
        guard let mimeType = mimeType?.lowercased() else { return true }
        return mimeType == "text/html" || mimeType == "application/xhtml+xml"
    }

    /// Whether `data` ends with the tag that closes a head, in any case.
    private static func endsHead(_ data: Data) -> Bool {
        guard data.count >= headEnd.count else { return false }
        return zip(data.suffix(headEnd.count), headEnd).allSatisfy { byte, expected in
            (byte | 0x20) == (expected | 0x20)
        }
    }

    private static func publicResourceURL(_ url: URL) -> URL? {
        guard ["http", "https"].contains(url.scheme?.lowercased()),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            components.host != nil
        else { return nil }
        components.user = nil
        components.password = nil
        components.fragment = nil
        return components.url
    }

    private final class PublicResourceDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            guard let url = request.url.flatMap(BrowserFaviconResourceLoader.publicResourceURL) else {
                completionHandler(nil)
                return
            }
            var request = request
            request.url = url
            request.httpShouldHandleCookies = false
            for header in ["Cookie", "Referer", "Authorization", "Proxy-Authorization"] {
                request.setValue(nil, forHTTPHeaderField: header)
            }
            completionHandler(request)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                completionHandler(.performDefaultHandling, nil)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}
