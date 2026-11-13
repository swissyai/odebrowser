import Foundation

/// The connection every ChatGPT request uses: nothing cached or stored, and
/// no redirect followed, so a request body never reaches another origin.
enum ChatGPTNetwork {
    // MARK: - Static Variables

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration, delegate: RefusingRedirects(), delegateQueue: nil)
    }()

    private final class RefusingRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }
}
