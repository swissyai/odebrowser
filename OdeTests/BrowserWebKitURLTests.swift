import Foundation
import XCTest

@testable import Ode

final class BrowserWebKitURLTests: XCTestCase {
    func testWebKitBlankPageFragmentsKeepTheirEscaping() throws {
        let native = try XCTUnwrap(URL(string: "about:blank%23one%2523two"))
        XCTAssertEqual(native.webKitPageURL.absoluteString, "about:blank#one%2523two")
    }

    func testOtherPathsAreNotDecoded() throws {
        for address in ["about:blank%2523one", "https://example.test/blank%23one", "about:blank#one"] {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertEqual(url.webKitPageURL, url)
        }
    }
}
