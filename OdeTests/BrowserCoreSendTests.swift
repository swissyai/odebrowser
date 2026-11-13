import OSLog
import XCTest

@testable import Ode

/// A core call nothing waits on, such as releasing a page, is not dropped when
/// the core refuses it: the refusal is logged with the intent's name and the
/// rule that refused it, never the page or address it named.
@MainActor
final class BrowserCoreSendTests: XCTestCase {
    func testARefusedReleaseIsLoggedNotSwallowed() throws {
        let started = Date.now
        let core = OdeCore()
        let pageID = UUID()
        XCTAssertThrowsError(try core.send(ReleasePage(pageID: pageID, keepsState: false)))

        CorePage(id: pageID, core: core).release(keepingState: false)

        let log = try OSLogStore(scope: .currentProcessIdentifier)
        let messages = try log.getEntries(
            at: log.position(date: started),
            matching: NSPredicate(format: "subsystem == %@ AND category == %@", "com.odebrowser.ode", "Pages")
        ).compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
        XCTAssertTrue(messages.contains { $0.hasPrefix("The core refused ReleasePage: ") }, "\(messages)")
        XCTAssertFalse(messages.contains { $0.contains(pageID.uuidString) }, "\(messages)")
    }
}
