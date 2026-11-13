import XCTest

@testable import OdeMobile

final class BrowserCommandLinkTests: XCTestCase {
    func testOnlyTheExactQuerylessFreshCommandRouteIsAccepted() throws {
        let accepted = try XCTUnwrap(URL(string: "ode://command/new"))
        XCTAssertEqual(BrowserCommandLink(url: accepted), .newQuery)
        XCTAssertEqual(BrowserCommandLink.newQuery.url, accepted)
        for spelling in [
            "https://command/new", "ode://open/new", "ode://command", "ode://command/new/",
            "ode://command/new/extra", "ode://command//new", "ode://command/%6Eew",
            "ode://command/new?", "ode://command/new?query=hello", "ode://command/new#",
            "ode://command/new#fragment", "ode://user@command/new", "ode://user:password@command/new",
            "ode://command:42/new", "ode://command:0/new", "ode://command/old/../new",
        ] {
            XCTAssertNil(BrowserCommandLink(url: try XCTUnwrap(URL(string: spelling))), spelling)
        }
        let webURL = try XCTUnwrap(URL(string: "https://example.com/shared"))
        let shared = try XCTUnwrap(BrowserSharedLink(url: webURL))
        XCTAssertNil(BrowserCommandLink(url: shared.handOffURL))
        XCTAssertEqual(BrowserSharedLink(handOffURL: shared.handOffURL), shared)
        XCTAssertNil(BrowserSharedLink(handOffURL: accepted))
    }
}
