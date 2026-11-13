import XCTest

@testable import OdeMobile

/// The share extension hands links to the app through a URL any app can
/// open, so these protect what that hand-off carries and accepts.
final class BrowserSharedLinkTests: XCTestCase {
    func testHandOffAcceptsOnlyAWebLinkThroughOdeOpen() throws {
        let rejected = [
            "https://example.com",
            "ode://other?url=https%3A%2F%2Fexample.com",
            "ode://open/path?url=https%3A%2F%2Fexample.com",
            "ode://open",
            "ode://open?url=",
            "ode://open?url=javascript%3Aalert(1)",
            "ode://open?url=file%3A%2F%2F%2Fetc%2Fpasswd",
            "ode://open?url=data%3Atext%2Fhtml%2Chi",
            "ode://open?url=https%3A%2F%2F",
            "ode://open?url=ode%3A%2F%2Fopen%3Furl%3Dhttps%253A%252F%252Fexample.com",
            "ode://open?url=https%3A%2F%2Fa.com&url=https%3A%2F%2Fb.com",
        ]
        for string in rejected {
            let url = try XCTUnwrap(URL(string: string), string)
            XCTAssertNil(BrowserSharedLink(handOffURL: url), string)
        }

        let accepted = try XCTUnwrap(URL(string: "ODE://open?url=http%3A%2F%2Fexample.com&later=1"))
        XCTAssertEqual(BrowserSharedLink(handOffURL: accepted)?.url.absoluteString, "http://example.com")
    }
}
