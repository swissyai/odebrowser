import Foundation
import XCTest

@testable import Ode

/// Finding the icon of a page no tab loaded reads the page's head through the
/// public loader: never a cookie, credential or referrer, never the page's
/// query or fragment, and never a link inside a comment or a script. A page
/// that moved to a sign-in on another site keeps its own site's icon.
final class BrowserSiteIconFinderTests: XCTestCase {
    func testTheHeadsLargeIconIsFoundWithoutCredentialsQueryOrHiddenLinks() async throws {
        let server = try BrowserPrivacyHTTPServer()
        let page = """
            <!doctype html><html><head><title>A <link rel="icon" href="/title.png"></title>
            <!-- <link rel="icon" href="/commented.png"> -->
            <link rel="icon" href="/small.png" sizes="16x16">
            <link rel=apple-touch-icon href=/touch.png>
            <link rel="shortcut icon" href="/large.png?v=1&amp;size=96" sizes="96x96">
            <script>document.write('<link rel="icon" href="/script.png">')</script>
            </head><body><link rel="icon" href="/body.png"></body></html>
            """
        server.overrideResponse = { request in
            switch request.path {
            case "/app/page": ("200 OK", "Content-Type: text/html; charset=utf-8\r\n", Data(page.utf8))
            case "/large.png": ("200 OK", "Content-Type: image/png\r\n", SiteIconFixture.png(side: 96))
            case "/small.png": ("200 OK", "Content-Type: image/png\r\n", SiteIconFixture.png(side: 16))
            case "/touch.png": ("200 OK", "Content-Type: image/png\r\n", SiteIconFixture.png(side: 180))
            default: ("404 Not Found", "Content-Type: text/plain\r\n", Data("Missing".utf8))
            }
        }
        try await server.start()
        defer { server.stop() }
        let finder = BrowserSiteIconFinder()
        let address = try XCTUnwrap(
            URL(
                string:
                    "http://fixture-user:fixture-password@parent.localhost:\(server.port)/app/page?token=secret#inbox"))

        let found = await finder.icon(for: address, profileID: UUID())
        let finding = try XCTUnwrap(found)

        XCTAssertEqual(finding.iconURL.path, "/large.png")
        XCTAssertEqual(finding.relation, .icon)
        XCTAssertEqual(finding.image.side, 96)
        let requests = server.requests
        attach(requests.map(\.description).joined(separator: "\n"), name: "Site icon wire requests")
        let pageRequest = try XCTUnwrap(requests.first { $0.path == "/app/page" })
        XCTAssertNil(pageRequest.query, "The page is asked for without its query")
        for request in requests {
            XCTAssertNil(request.headers["cookie"], request.description)
            XCTAssertNil(request.headers["referer"], request.description)
            XCTAssertNil(request.headers["authorization"], request.description)
        }
        let fetched = Set(requests.map(\.path))
        XCTAssertTrue(
            fetched.isDisjoint(with: ["/title.png", "/commented.png", "/script.png", "/body.png", "/touch.png"]))
    }

    func testAPageThatMovedToASignInElsewhereKeepsItsOwnSitesIcon() async throws {
        let server = try BrowserPrivacyHTTPServer()
        let port = server.port
        server.overrideResponse = { request in
            switch (request.host.split(separator: ":").first.map(String.init), request.path) {
            case ("mail.localhost", "/inbox"):
                ("302 Found", "Location: http://accounts.localhost:\(port)/signin\r\n", Data())
            case ("mail.localhost", "/favicon.ico"):
                ("200 OK", "Content-Type: image/png\r\n", SiteIconFixture.png(side: 32, red: 0.1))
            case ("accounts.localhost", "/signin"):
                (
                    "200 OK", "Content-Type: text/html\r\n",
                    Data(#"<head><link rel="icon" sizes="128x128" href="/brand.png"></head>"#.utf8)
                )
            case ("accounts.localhost", "/brand.png"):
                ("200 OK", "Content-Type: image/png\r\n", SiteIconFixture.png(side: 128))
            default: ("404 Not Found", "Content-Type: text/plain\r\n", Data())
            }
        }
        try await server.start()
        defer { server.stop() }
        let finder = BrowserSiteIconFinder()

        let found = await finder.icon(for: server.url(host: "mail.localhost", path: "/inbox"), profileID: UUID())
        let finding = try XCTUnwrap(found)

        XCTAssertEqual(finding.iconURL.host(), "mail.localhost")
        XCTAssertEqual(finding.relation, .defaultIcon)
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
