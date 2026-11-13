import XCTest

@testable import Ode

final class BrowserShortcutPolicyTests: XCTestCase {
    func testSearchPolicyRequiresEveryTermAndExactSingleCharacterTokens() {
        let fields = [
            "Copy Page Link",
            "Page",
            "copy url address clipboard",
            "command shift c",
        ]

        XCTAssertTrue(
            BrowserShortcutSearchDocument(fields: fields).matches("copy url")
        )
        XCTAssertTrue(
            BrowserShortcutSearchDocument(fields: fields).matches("command shift c")
        )
        XCTAssertFalse(
            BrowserShortcutSearchDocument(fields: fields).matches("command shift p")
        )
        XCTAssertTrue(
            BrowserShortcutSearchDocument(fields: fields).matches("")
        )
    }
}
