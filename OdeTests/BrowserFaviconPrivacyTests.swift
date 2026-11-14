import AppKit
import Foundation
import Network
import WebKit
import XCTest

@testable import Ode

@MainActor
final class BrowserFaviconPrivacyTests: XCTestCase {
    private var navigations: [FaviconPrivacyNavigation] = []

    func testCapturePreservesCookieScopeAndSpaceIsolationAcrossResourceRedirects() async throws {
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        defer { server.stop() }
        let pageURL = server.url(host: "parent.localhost", path: "/private/page?secret=query#fragment")
        let webView = makeWebView()
        try await load(server.url(host: "other.localhost", path: "/same-site-cookies"), in: webView)
        try await load(pageURL, in: webView)
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertTrue(cookies.contains { $0.name == "hostOnly" })
        XCTAssertTrue(cookies.contains { $0.name == "domainCookie" })
        XCTAssertTrue(cookies.contains { $0.name == "strictOther" })
        XCTAssertTrue(cookies.contains { $0.name == "laxOther" })
        XCTAssertEqual(cookies.first { $0.name == "hostOnly" }?.domain, "parent.localhost")
        XCTAssertEqual(cookies.first { $0.name == "domainCookie" }?.domain, ".parent.localhost")
        attach(
            cookies.map {
                "\($0.name): domain=\($0.domain), path=\($0.path), secure=\($0.isSecure), properties=\($0.properties ?? [:])"
            }.joined(separator: "\n"), name: "WebKit cookie representation")

        // A second Space has a distinct store even while both pages are alive.
        let otherSpace = makeWebView()
        try await load(server.url(host: "parent.localhost", path: "/other-space"), in: otherSpace)
        try await webView.evaluateJavaScript(
            """
            document.head.innerHTML = '<link rel="manifest" href="/private/manifest-redirect">';
            """)
        let data = await BrowserFaviconCapture.capture(from: webView)
        XCTAssertNotNil(data, "An authenticated manifest and icon must remain discoverable")

        let requests = server.requests.filter {
            ($0.path.contains("manifest") || $0.path.contains("icon")) && $0.headers["sec-fetch-dest"] != "manifest"
        }
        attach(requests.map(\.description).joined(separator: "\n"), name: "Resource wire requests")
        for path in [
            "/private/manifest-redirect", "/private/manifest.json", "/child-icon", "/private/cross-site-icon-redirect",
            "/same-site-icon", "/privateer/icon", "/private/icon-redirect", "/public/icon",
        ] {
            XCTAssertTrue(requests.contains { $0.path == path }, "Missing wire capture for \(path)")
        }
        for request in requests {
            let cookie = request.headers["cookie", default: ""]
            XCTAssertNil(request.headers["referer"], request.description)
            XCTAssertFalse(cookie.contains("spaceB="), request.description)
            XCTAssertFalse(cookie.contains("strictOther="), request.description)
            XCTAssertFalse(cookie.contains("laxOther="), request.description)
            // WebKit permits Secure cookies on trustworthy localhost HTTP.
            // Native fallback requests must never carry them.
            if request.headers["sec-fetch-mode"] == nil {
                XCTAssertFalse(cookie.contains("secureOnly="), request.description)
            }
            if request.host.hasPrefix("child.") {
                XCTAssertFalse(cookie.contains("hostOnly="), request.description)
            }
            if !request.path.hasPrefix("/private/") {
                XCTAssertFalse(cookie.contains("privatePath="), request.description)
            }
        }
        let authenticated = requests.filter { $0.path == "/private/manifest.json" || $0.path == "/public/icon" }
        XCTAssertEqual(authenticated.count, 2)
        XCTAssertTrue(authenticated.allSatisfy { $0.headers["cookie", default: ""].contains("hostOnly=spaceA") })
        withExtendedLifetime(otherSpace) {}
    }

    func testCaptureOmitsReferrersForDocumentAndElementPolicies() async throws {
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        defer { server.stop() }
        for policy in ["no-referrer", "origin"] {
            let webView = makeWebView()
            try await load(
                server.url(host: "parent.localhost", path: "/policy/\(policy)?secret=query#fragment"), in: webView)
            try await webView.evaluateJavaScript(
                """
                document.head.innerHTML += '<link rel="manifest" href="http://child.parent.localhost:\(server.port)/policy-manifest-redirect"><link rel="icon" referrerpolicy="\(policy)" href="http://child.parent.localhost:\(server.port)/policy-icon-redirect?case=\(policy)">';
                """)
            let data = await BrowserFaviconCapture.capture(from: webView)
            XCTAssertNotNil(data, "Public cross-origin icons without CORS must still load")
        }
        let requests = server.requests.filter {
            ($0.path.hasPrefix("/policy-icon") || $0.path.hasPrefix("/policy-manifest"))
                && $0.headers["sec-fetch-dest"] != "manifest"
        }
        attach(requests.map(\.description).joined(separator: "\n"), name: "Policy wire requests")
        for path in [
            "/policy-manifest-redirect", "/policy-manifest.json", "/policy-manifest-icon-redirect",
            "/policy-manifest-icon", "/policy-icon-redirect", "/policy-icon",
        ] {
            XCTAssertGreaterThanOrEqual(requests.filter { $0.path == path }.count, 2)
        }
        for request in requests {
            XCTAssertNil(request.headers["referer"], request.description)
            XCTAssertNil(request.headers["authorization"], request.description)
        }
    }

    func testNativeFallbackOmitsURLCredentialsCookiesAndReferrersAcrossRedirects() async throws {
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        defer { server.stop() }
        let url = URL(
            string:
                "http://fixture-user:fixture-password@parent.localhost:\(server.port)/credential-icon-redirect#fragment"
        )!
        let data = await BrowserFaviconFallbackLoader.download(url)
        XCTAssertNotNil(data)
        let denied = await BrowserFaviconFallbackLoader.download(
            server.url(host: "parent.localhost", path: "/auth-icon"))
        XCTAssertNil(denied)
        let requests = server.requests
        attach(requests.map(\.description).joined(separator: "\n"), name: "Native credentials wire requests")
        XCTAssertTrue(requests.contains { $0.host.hasPrefix("child.") })
        for request in requests {
            XCTAssertNil(request.headers["referer"], request.description)
            XCTAssertNil(request.headers["cookie"], request.description)
            XCTAssertNil(request.headers["authorization"], request.description)
        }
    }

    func testOversizedIconsAndManifestsStopBeforeTheResponseFinishes() async throws {
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        defer { server.stop() }
        // The server streams for at least five seconds unless canceled. A
        // post-download size check cannot finish within this budget.
        let start = ContinuousClock.now
        let native = await BrowserFaviconFallbackLoader.download(
            server.url(host: "parent.localhost", path: "/oversized-icon"))
        XCTAssertNil(native)
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))

        let webView = makeWebView()
        try await load(server.url(host: "parent.localhost", path: "/policy/no-referrer"), in: webView)
        try await webView.evaluateJavaScript(
            """
            document.head.innerHTML = '<link rel="manifest" href="/oversized-manifest"><link rel="icon" href="/oversized-icon">';
            """)
        let captureStart = ContinuousClock.now
        let captured = await BrowserFaviconCapture.capture(from: webView)
        XCTAssertNil(captured)
        XCTAssertLessThan(captureStart.duration(to: .now), .seconds(3))
        let requests = server.requests.filter {
            $0.path.hasPrefix("/oversized-") && $0.headers["sec-fetch-dest"] != "manifest"
        }
        XCTAssertTrue(requests.contains { $0.path == "/oversized-manifest" && $0.headers["sec-fetch-mode"] == "cors" })
        XCTAssertTrue(requests.contains { $0.path == "/oversized-manifest" && $0.headers["sec-fetch-mode"] == nil })
    }

    // Temporary diagnostic-branch calibration, not a replacement for the
    // privacy cases above. Both variants keep their original isolated store.
    func testDiagnosticSVGCanvasUnattachedVersusHosted() async throws {
        guard ProcessInfo.processInfo.environment["ODE_NATIVE_CI_DIAGNOSTICS"] == "1" else { return }
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        defer { server.stop() }
        let svg = Data(
            #"<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="blue"/></svg>"#
                .utf8)
        // Every diagnostic operation spends the same existing 15-second
        // fixture budget, including a backend that never calls toBlob back.
        let deadline = Date().addingTimeInterval(15)
        for hosted in [false, true] {
            guard Date() < deadline else { break }
            let webView = makeWebView()
            let window: NSWindow?
            if hosted {
                // Use the native test host's placement/safety policy, never a
                // bespoke far-offscreen window or a host-wide policy change.
                let host = NSWindow(
                    contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                host.isReleasedWhenClosed = false
                host.collectionBehavior = [.transient, .ignoresCycle]
                host.ignoresMouseEvents = true
                host.contentView = webView
                host.orderFront(nil)
                window = host
                XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(host.frame) })
                XCTAssertTrue(host.collectionBehavior.contains(.transient))
                XCTAssertFalse(NSApp.isActive)
            } else {
                window = nil
            }
            defer {
                webView.stopLoading()
                window?.contentView = nil
                window?.close()
            }
            let navigation = FaviconPrivacyNavigation(trustedPort: nil)
            navigations.append(navigation)
            webView.navigationDelegate = navigation
            webView.load(URLRequest(url: server.url(host: "parent.localhost", path: "/policy/no-referrer")))
            await fulfillment(of: [navigation.finished], timeout: max(0, deadline.timeIntervalSinceNow))
            if let error = navigation.error { throw error }
            guard Date() < deadline else { break }
            print("ODE_NATIVE_CI favicon calibration hosted=\(hosted) attached=\(webView.window != nil)")
            // Each option gets a fresh canvas: a second getContext call cannot
            // change an existing context's allocation attributes.
            for software in [false, true] {
                let control: String? = await diagnosticResult(before: deadline) {
                    try await webView.callAsyncJavaScript(
                        """
                        const canvas = document.createElement('canvas');
                        canvas.width = 32;
                        canvas.height = 32;
                        const context = software
                            ? canvas.getContext('2d', {willReadFrequently: true}) : canvas.getContext('2d');
                        if (!context) return 'no-context';
                        context.fillStyle = 'rgb(17, 34, 51)';
                        context.fillRect(0, 0, 32, 32);
                        let pixel = 'unavailable';
                        try {
                            const p = context.getImageData(16, 16, 1, 1).data;
                            pixel = p[0] === 17 && p[1] === 34 && p[2] === 51 && p[3] === 255
                                ? 'match' : 'mismatch';
                        } catch (_) { pixel = 'error'; }
                        let url = 'error';
                        try {
                            const value = canvas.toDataURL('image/png');
                            url = value === 'data:,' ? 'empty-sentinel'
                                : value.startsWith('data:image/png;base64,') ? 'png' : 'other';
                        } catch (_) {}
                        const blob = await new Promise(resolve => {
                            let done = false;
                            const finish = value => {
                                if (done) return;
                                done = true;
                                clearTimeout(timer);
                                resolve(value);
                            };
                            const timer = setTimeout(() => finish('timeout'), Math.max(0, deadline - Date.now()));
                            try {
                                canvas.toBlob(value => finish(value === null ? 'null'
                                    : value.size === 0 ? 'empty' : value.size <= 1048576 ? 'small' : 'large'), 'image/png');
                            } catch (_) { finish('error'); }
                        });
                        return `${pixel}/${url}/${blob}`;
                        """, arguments: ["software": software, "deadline": deadline.timeIntervalSince1970 * 1000],
                        in: nil, contentWorld: .defaultClient) as? String
                }
                // Validate every field before logging; never echo a JS payload.
                let fields = control?.split(separator: "/").map(String.init) ?? []
                let pixels = ["match", "mismatch", "error", "unavailable"]
                let urls = ["empty-sentinel", "png", "other", "error"]
                let blobs = ["null", "empty", "small", "large", "timeout", "error"]
                if fields.count == 3, pixels.contains(fields[0]), urls.contains(fields[1]), blobs.contains(fields[2]) {
                    print(
                        "ODE_NATIVE_CI favicon calibration software=\(software) pixel=\(fields[0]) "
                            + "url=\(fields[1]) blob=\(fields[2])")
                } else {
                    print("ODE_NATIVE_CI favicon calibration software=\(software) result=unavailable")
                }
            }
            let svgPresent: Bool? = await diagnosticResult(before: deadline) {
                await BrowserFaviconCapture.rasterizedSVGData(svg, in: webView) != nil
            }
            print("ODE_NATIVE_CI favicon calibration svgPresent=\(svgPresent == true) available=\(svgPresent != nil)")
        }
        let sharedPresent: Bool? = await diagnosticResult(before: deadline) {
            await BrowserFaviconSVGRasterizer.png(from: svg, pixelSize: 128, tint: nil) != nil
        }
        print(
            "ODE_NATIVE_CI favicon calibration sharedPresent=\(sharedPresent == true) available=\(sharedPresent != nil)"
        )
    }

    // Native completion bounds even a stalled WebContent process. Cancellation
    // cannot force WebKit's callback, so no further work follows it in the task.
    private func diagnosticResult<Value>(
        before deadline: Date, operation: @escaping @MainActor () async throws -> Value?
    ) async -> Value? {
        guard Date() < deadline else { return nil }
        let finished = XCTestExpectation(description: "Canvas diagnostic completion")
        var result: Value?
        let task = Task { @MainActor in
            defer { finished.fulfill() }
            result = try? await operation()
        }
        defer { task.cancel() }
        await fulfillment(of: [finished], timeout: max(0, deadline.timeIntervalSinceNow))
        return result
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
    }

    private func load(_ url: URL, in webView: WKWebView) async throws {
        let navigation = FaviconPrivacyNavigation(trustedPort: url.scheme == "https" ? url.port : nil)
        navigations.append(navigation)
        webView.navigationDelegate = navigation
        webView.load(URLRequest(url: url))
        await fulfillment(of: [navigation.finished], timeout: 15)
        if let error = navigation.error { throw error }
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class FaviconPrivacyNavigation: NSObject, WKNavigationDelegate {
    let finished = XCTestExpectation(description: "Fixture navigation")
    var error: Error?
    let trustedPort: Int?

    init(trustedPort: Int?) { self.trustedPort = trustedPort }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.host == "parent.localhost",
            challenge.protectionSpace.port == trustedPort,
            let trust = challenge.protectionSpace.serverTrust
        {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = error
        finished.fulfill()
    }
}
