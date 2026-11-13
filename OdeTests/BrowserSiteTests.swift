import JavaScriptCore
import XCTest

@testable import Ode

/// A page's site is its host in lowercase, without a final dot, and without a
/// leading "www." when a domain remains after it, whatever the scheme, port or
/// path. Boosts, remembered page backgrounds and blocked-load counts name a
/// page's site by this one rule, and the Boost page script names the same site
/// for every host the Swift side does.
@MainActor
final class BrowserSiteTests: XCTestCase {
    /// Hosts as a page's `location.hostname` and a URL's host spell them.
    private let hosts = [
        "example.com", "Example.COM", "www.example.com", "WWW.Example.com.", "example.com.", "www.com", "www.com.",
        "www", "www.", ".", "", "news.example.com", "www.www.example.com", "wwwexample.com", "www.co.uk",
        "localhost", "127.0.0.1", "[::1]", "xn--bcher-kva.de", "example.com..",
    ]

    func testASiteIsItsHostWithoutCaseFinalDotOrALeadingWww() {
        XCTAssertEqual(BrowserSite.of(URL(string: "https://WWW.Example.com./path?q=1")), "example.com")
        XCTAssertEqual(BrowserSite.of(URL(string: "http://news.example.com:8080/")), "news.example.com")
        XCTAssertEqual(BrowserSite.of(URL(string: "https://www.com/")), "www.com")
        XCTAssertEqual(BrowserSite.of(URL(string: "https://user:secret@www.example.com/")), "example.com")
        XCTAssertNil(BrowserSite.of(URL(string: "file:///Users/someone/page.html")))
        XCTAssertNil(BrowserSite.of(URL(string: "about:blank")))
        XCTAssertNil(BrowserSite.of(nil))
        XCTAssertNil(BrowserSite.of(host: "."))
    }

    func testThePageScriptNamesTheSameSiteForEveryHost() throws {
        let context = try XCTUnwrap(JSContext())
        let siteOf = try XCTUnwrap(context.evaluateScript("(\(BrowserSite.javaScript))"))
        XCTAssertNil(context.exception)
        for host in hosts {
            let scripted = siteOf.call(withArguments: [host])?.toString()
            XCTAssertEqual(scripted, BrowserSite.of(host: host) ?? "", "host \(host)")
        }
    }

    func testBackgroundsAndBlockedLoadsNameAPageByItsSite() {
        let profile = UUID()
        let color = BrowserPageBackground(red: 0.1, green: 0.2, blue: 0.3)
        let backgrounds = BrowserSiteBackgrounds(file: nil)
        backgrounds.record(color, for: URL(string: "https://example.com./a"), in: profile, isPrivate: false)
        XCTAssertEqual(backgrounds.background(for: URL(string: "https://WWW.Example.com/b"), in: profile), color)
        // Only web pages paint a background worth remembering.
        backgrounds.record(color, for: URL(string: "ftp://files.example/"), in: profile, isPrivate: false)
        XCTAssertNil(backgrounds.background(for: URL(string: "ftp://files.example/"), in: profile))

        let blocked = BrowserPageBlockedLoads()
        blocked.record(URL(string: "https://WWW.Tracker.example./pixel.gif")!, by: "balanced")
        blocked.record(URL(string: "https://www.com/pixel.gif")!, by: "balanced")
        XCTAssertEqual(blocked.countsBySite, ["tracker.example": 1, "www.com": 1])
    }
}
