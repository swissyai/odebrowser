import Foundation

/// Where a build that is not shipping sends the requests the Command Bar
/// makes to live services: search suggestions, Wikipedia lookups and typed
/// page navigations from the Mac palette or Quick Window. A test host or
/// harness launch that names a fixture server in its environment sends them
/// there, under the host they were for,
/// as `http://127.0.0.1:8765/en.wikipedia.org/api/rest_v1/…`; one that names
/// none sends them nowhere, so no test or harness run reaches a live service
/// with Ode's name in its headers. A shipping build sends each request where
/// the core named it.
enum BrowserNetworkFixture {
    // MARK: - Static Variables

    /// The launch environment key that names the fixture server.
    static let environmentKey = "ODE_NETWORK_FIXTURE"

    /// Fixture responses are terminal: a redirect must never carry the
    /// client's headers outside the local fixture server.
    static let redirectGuard: any URLSessionTaskDelegate = RedirectGuard()

    // MARK: - Actions - Routing

    /// `address` as this build may fetch it: unchanged in a shipping build
    /// or an ordinary launch; on the fixture server in a test or harness run
    /// that names one; nil in a test or harness run that names none.
    static func routed(_ address: URL) -> URL? {
        #if DEBUG || ODE_REVIEW_BUILD
            routed(address, environment: ProcessInfo.processInfo.environment, isTestHost: isTestHost)
        #else
            isTestHost || ProcessInfo.processInfo.environment["ODE_TEST_HARNESS"] == "1" ? nil : address
        #endif
    }

    /// A page navigation from the Command Bar or a typed Quick Window.
    /// Local pages stay local; public destinations use the same fixture
    /// boundary as background lookups, including refusing them without one.
    static func navigation(_ address: URL) -> URL? {
        guard ["http", "https"].contains(address.scheme?.lowercased() ?? "") else { return address }
        if let host = address.host(), ["127.0.0.1", "localhost", "::1"].contains(host) { return address }
        return routed(address)
    }

    #if DEBUG || ODE_REVIEW_BUILD
        /// `address` as a run with `environment` may fetch it, in a test host
        /// or not.
        static func routed(_ address: URL, environment: [String: String], isTestHost: Bool) -> URL? {
            if let server = environment[environmentKey].flatMap(fixtureServer(_:)) {
                guard let host = address.host(),
                    var components = URLComponents(url: server, resolvingAgainstBaseURL: false)
                else { return nil }
                let original = URLComponents(url: address, resolvingAgainstBaseURL: false)
                components.percentEncodedPath = "/" + host + (original?.percentEncodedPath ?? "")
                components.percentEncodedQuery = original?.percentEncodedQuery
                return components.url
            }
            return isTestHost || environment["ODE_TEST_HARNESS"] == "1" ? nil : address
        }

        /// The fixture server `value` names, only as plain http on this Mac.
        private static func fixtureServer(_ value: String) -> URL? {
            guard let url = URL(string: value), url.scheme == "http",
                let host = url.host(), ["127.0.0.1", "localhost", "::1"].contains(host)
            else { return nil }
            return url
        }

    #endif

    /// Whether this process hosts tests, including a Release test host.
    private static var isTestHost: Bool { NSClassFromString("XCTestCase") != nil }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
