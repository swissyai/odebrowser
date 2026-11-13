import XCTest

@testable import Ode

@MainActor
final class BrowserFeedbackDraftTests: XCTestCase {
    // MARK: - Actions - Privacy and Encoding

    func testContextIsOptInAndExactlyTheVisibleAllowlistInBothExports() async throws {
        let draft = makeDraft()
        draft.report = "A user-written report"
        XCTAssertFalse(draft.includesAppDetails)
        XCTAssertEqual(draft.body, draft.report)
        XCTAssertFalse(draft.copyText.contains(draft.appDetails))
        XCTAssertEqual(try query(draft)["body"], draft.report)

        draft.includesAppDetails = true
        XCTAssertEqual(draft.body, draft.report + "\n\n" + draft.appDetails)
        XCTAssertTrue(draft.appDetails.contains("version-sentinel"))
        XCTAssertTrue(draft.appDetails.contains("build-sentinel"))
        XCTAssertTrue(draft.appDetails.contains("26.1.2"))
        XCTAssertTrue(draft.copyText.hasSuffix(draft.body))
        XCTAssertEqual(try query(draft)["body"], draft.body)

        draft.includesAppDetails = false
        XCTAssertEqual(try query(draft)["body"], draft.report)
        XCTAssertFalse(draft.copyText.contains(draft.appDetails))
    }

    func testReservedCharactersRoundTripWithoutChangingRecipientOrAddingHeaders() async throws {
        let draft = makeDraft()
        draft.topic = "Idea & cc=other@example.test\r\nBcc: injected@example.test + ? # % 🦉"
        draft.report = "Hello 世界 🦉\n&bcc=other@example.test?x=1+#%\r\nSubject: unchanged"
        let url = try XCTUnwrap(draft.mailtoURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, "feedback@odebrowser.com")
        XCTAssertNil(components.host)
        XCTAssertNil(components.fragment)
        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(items.map(\.name), ["subject", "body"])
        XCTAssertEqual(items[0].value, draft.subject)
        XCTAssertFalse(draft.subject.contains("\r"))
        XCTAssertFalse(draft.subject.contains("\n"))
        XCTAssertEqual(items[1].value, draft.report)
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        XCTAssertTrue(url.absoluteString.contains("%26"))
    }

    func testBlankReportsNeverInvokeSystemBoundaries() async {
        let draft = makeDraft()
        draft.report = " \t\r\n "
        draft.topic = "A topic alone is not a report"
        draft.includesAppDetails = true
        draft.openEmail { _, _ in XCTFail("Blank report opened email") }
        draft.copyReport { _ in
            XCTFail("Blank report copied")
            return true
        }
        XCTAssertNil(draft.mailtoURL)
        XCTAssertEqual(draft.status, .empty)
    }

    func testOversizedEncodedReportUsesFullCopyInsteadOfTruncating() async throws {
        let draft = makeDraft()
        draft.report = String(repeating: "🦉 & +\n", count: 400)
        draft.includesAppDetails = true
        let original = draft.report
        XCTAssertLessThan(original.utf8.count, BrowserFeedbackDraft.maximumMailtoBytes)
        XCTAssertNil(draft.mailtoURL)
        draft.openEmail { _, _ in XCTFail("Oversized report opened email") }
        XCTAssertEqual(draft.status, .tooLong)
        var copied: String?
        draft.copyReport {
            copied = $0
            return true
        }
        XCTAssertEqual(copied, draft.copyText)
        XCTAssertTrue(try XCTUnwrap(copied).contains(original))
        XCTAssertTrue(try XCTUnwrap(copied).contains("feedback@odebrowser.com"))
        XCTAssertEqual(draft.report, original)
    }

    // MARK: - Actions - Draft and Failure Retention

    func testEntryPrefillsNeverOverwriteAnExistingDraftOrTopic() async {
        let draft = makeDraft()
        draft.prepare(topic: "Browser import")
        draft.prepare(topic: "Issue")
        XCTAssertEqual(draft.topic, "Browser import")
        draft.topic = ""
        draft.report = "My existing report"
        draft.prepare(topic: "Issue")
        XCTAssertEqual(draft.topic, "")
        XCTAssertEqual(draft.report, "My existing report")
        draft.includesAppDetails = true
        draft.prepare(topic: nil)
        XCTAssertEqual(draft.report, "My existing report")
        XCTAssertTrue(draft.includesAppDetails)
        XCTAssertTrue(makeDraft().report.isEmpty)
        XCTAssertFalse(makeDraft().includesAppDetails)
    }

    func testHandoffSuccessAndFailureRetainEditsAndRejectConcurrentAttempts() async {
        for accepted in [false, true] {
            let draft = makeDraft()
            draft.report = "Original report"
            draft.topic = "Original topic"
            var completion: (@MainActor (Bool) -> Void)?
            draft.openEmail { _, callback in completion = callback }
            XCTAssertTrue(draft.isOpeningEmail)
            draft.openEmail { _, _ in XCTFail("Duplicate concurrent handoff") }
            draft.report = "Edited while email opens"
            draft.topic = "Edited topic"
            draft.includesAppDetails = true
            completion?(accepted)
            XCTAssertFalse(draft.isOpeningEmail)
            XCTAssertEqual(draft.status, accepted ? .opened : .unavailable)
            XCTAssertEqual(draft.report, "Edited while email opens")
            XCTAssertEqual(draft.topic, "Edited topic")
            XCTAssertTrue(draft.includesAppDetails)
        }
    }

    func testCopyFailureAndLateHandoffDoNotLoseDraftOrReplaceNewerCopyStatus() async {
        let draft = makeDraft()
        draft.report = "Keep all of this"
        var completion: (@MainActor (Bool) -> Void)?
        draft.openEmail { _, callback in completion = callback }
        draft.copyReport { _ in false }
        XCTAssertEqual(draft.status, .copyFailed)
        completion?(true)
        XCTAssertEqual(draft.status, .copyFailed)
        XCTAssertEqual(draft.report, "Keep all of this")
        draft.copyReport { _ in true }
        XCTAssertEqual(draft.status, .copied)
        XCTAssertEqual(draft.report, "Keep all of this")
    }

    // MARK: - Actions - Fixtures

    private func makeDraft() -> BrowserFeedbackDraft {
        BrowserFeedbackDraft(
            version: "version-sentinel", build: "build-sentinel",
            osVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 2)
        )
    }

    private func query(_ draft: BrowserFeedbackDraft) throws -> [String: String] {
        let url = try XCTUnwrap(draft.mailtoURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}
