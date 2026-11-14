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

    func testEmailLinkAcceptanceAndFailureRetainEditsAndRejectConcurrentAttempts() async {
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
            XCTAssertEqual(draft.status, accepted ? .requested : .unavailable)
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

    // MARK: - Actions - Screenshot Ownership

    func testScreenshotPreparationIsOncePerDraftAndRemovalRejectsLateCapture() async throws {
        let draft = makeDraft()
        draft.report = "Keep the report"
        draft.topic = "Keep the topic"
        draft.includesAppDetails = true
        let attempt = try XCTUnwrap(draft.beginCapture())
        XCTAssertNil(draft.beginCapture(retake: true))
        draft.removeScreenshot()
        draft.finishCapture(attempt, png: Data([1, 2, 3]))
        XCTAssertNil(draft.screenshot)
        XCTAssertFalse(draft.isCapturing)
        XCTAssertNil(draft.beginCapture())
        XCTAssertEqual(draft.report, "Keep the report")
        XCTAssertEqual(draft.topic, "Keep the topic")
        XCTAssertTrue(draft.includesAppDetails)
    }

    func testRetakeFailureRetainsReviewedImageAndStaleCompletionCannotReplaceIt() async throws {
        let draft = makeDraft()
        let first = try XCTUnwrap(draft.beginCapture())
        let original = Data([1, 2, 3])
        draft.finishCapture(first, png: original)
        let retake = try XCTUnwrap(draft.beginCapture(retake: true))
        draft.finishCapture(first, png: Data([9]))
        XCTAssertTrue(draft.isCapturing)
        XCTAssertEqual(draft.screenshot, original)
        draft.finishCapture(retake, png: nil, message: "capture failed")
        XCTAssertEqual(draft.screenshot, original)
        XCTAssertNotNil(draft.captureMessage)
        XCTAssertFalse(draft.isCapturing)
        XCTAssertNil(draft.beginCapture())
    }

    func testCancelledCaptureRejectsLateImageAndAllowsPreparationFromNextWindow() async throws {
        let draft = makeDraft()
        draft.report = "Keep this draft"
        let abandoned = try XCTUnwrap(draft.beginCapture())
        draft.cancelCapture(abandoned)
        XCTAssertFalse(draft.isCapturing)
        let current = try XCTUnwrap(draft.beginCapture())
        draft.finishCapture(abandoned, png: Data([1]))
        draft.cancelCapture(abandoned)
        XCTAssertTrue(draft.isCapturing)
        XCTAssertNil(draft.screenshot)
        let reviewed = Data([2])
        draft.finishCapture(current, png: reviewed)
        let retake = try XCTUnwrap(draft.beginCapture(retake: true))
        draft.cancelCapture(retake)
        draft.finishCapture(retake, png: Data([3]))
        XCTAssertEqual(draft.screenshot, reviewed)
        XCTAssertNil(draft.beginCapture())
        XCTAssertEqual(draft.report, "Keep this draft")
    }

    func testFailedSubmissionRetainsExactlyReviewedPayloadAndRetryIdentity() async throws {
        let draft = makeDraft()
        draft.topic = "Window issue"
        draft.report = "The sidebar moved"
        draft.includesAppDetails = true
        let png = pngFixture
        draft.finishCapture(try XCTUnwrap(draft.beginCapture()), png: png)
        var first: BrowserFeedbackSubmission?
        await draft.send { submission in
            first = submission
            XCTAssertEqual(submission.topic, draft.topic)
            XCTAssertEqual(submission.report, draft.report)
            XCTAssertEqual(submission.appDetails, draft.appDetails)
            XCTAssertEqual(submission.screenshot?.base64, png)
            await draft.send { _ in XCTFail("A concurrent upload escaped the draft gate") }
            throw BrowserFeedbackSubmission.Failure.offline
        }
        XCTAssertEqual(draft.report, "The sidebar moved")
        XCTAssertEqual(draft.screenshot, png)
        XCTAssertTrue(draft.includesAppDetails)
        XCTAssertTrue(draft.canRetrySending)
        XCTAssertFalse(draft.isSending)
        await draft.send { submission in XCTAssertEqual(submission, first) }
        XCTAssertEqual(draft.status, .received)
        XCTAssertTrue(draft.report.isEmpty)
        XCTAssertTrue(draft.topic.isEmpty)
        XCTAssertNil(draft.screenshot)
        XCTAssertFalse(draft.includesAppDetails)
        XCTAssertFalse(draft.hasPreparedScreenshot)
    }

    func testAcknowledgmentNeverClearsEditsAndChangedPayloadGetsANewRequestIdentity() async throws {
        let draft = makeDraft()
        draft.report = "Original report"
        var acknowledged: UUID?
        await draft.send { submission in
            acknowledged = submission.requestID
            draft.report = "Edited while sending"
            draft.topic = "Keep this topic"
            draft.includesAppDetails = true
            draft.finishCapture(try XCTUnwrap(draft.beginCapture()), png: pngFixture)
        }
        XCTAssertEqual(draft.status, .receivedWithEdits)
        XCTAssertEqual(draft.report, "Edited while sending")
        XCTAssertEqual(draft.topic, "Keep this topic")
        XCTAssertEqual(draft.screenshot, pngFixture)
        XCTAssertTrue(draft.includesAppDetails)
        var failed: UUID?
        await draft.send { submission in
            XCTAssertNotEqual(submission.requestID, acknowledged)
            failed = submission.requestID
            throw BrowserFeedbackSubmission.Failure.unavailable
        }
        draft.removeScreenshot()
        draft.report = "A newer report"
        XCTAssertFalse(draft.canRetrySending)
        await draft.send { submission in
            XCTAssertNotEqual(submission.requestID, failed)
            XCTAssertEqual(submission.report, "A newer report")
            XCTAssertNil(submission.screenshot)
        }
        XCTAssertEqual(draft.status, .received)
    }

    func testInvalidOrCancelledSubmissionNeverDiscardsDraftOrInvokesAnInvalidUpload() async throws {
        let draft = makeDraft()
        draft.report = " \n "
        await draft.send { _ in XCTFail("Blank report uploaded") }
        XCTAssertEqual(draft.status, .empty)
        draft.report = String(repeating: "a", count: 20_001)
        await draft.send { _ in XCTFail("Oversized report uploaded") }
        XCTAssertEqual(draft.report.utf16.count, 20_001)
        draft.report = "Keep the reviewed report"
        await draft.send { _ in throw CancellationError() }
        XCTAssertEqual(draft.report, "Keep the reviewed report")
        XCTAssertTrue(draft.canRetrySending)
        draft.topic = String(repeating: "🦉", count: 81)
        await draft.send { _ in XCTFail("Oversized UTF-16 topic uploaded") }
        XCTAssertFalse(draft.isSending)
    }

    func testNewDraftEditsRetireReceiptWithoutHidingPendingOrUncertainSubmission() async throws {
        let edits: [@MainActor (BrowserFeedbackDraft) throws -> Void] = [
            { $0.report = "Another report" },
            { $0.topic = "Another topic" },
            { $0.includesAppDetails = true },
            { $0.finishCapture(try XCTUnwrap($0.beginCapture()), png: self.pngFixture) },
        ]
        for edit in edits {
            let draft = makeDraft()
            draft.report = "The acknowledged report"
            await draft.send { _ in }
            XCTAssertEqual(draft.status, .received)
            try edit(draft)
            XCTAssertNil(draft.status, "A prior receipt does not describe this new draft")
        }
        let draft = makeDraft()
        draft.report = "The pending report"
        await draft.send { _ in
            draft.report = "Edited while pending"
            XCTAssertEqual(draft.status, .sending)
            throw BrowserFeedbackSubmission.Failure.unconfirmed
        }
        let uncertain = draft.status
        draft.topic = "Keep the uncertainty visible"
        XCTAssertEqual(draft.status, uncertain)
        XCTAssertNotNil(draft.status)
        XCTAssertEqual(draft.report, "Edited while pending")
    }

    func testTextOnlyEmailLinkRetainsScreenshotAndDoesNotClaimAComposerAppeared() async throws {
        let draft = makeDraft()
        draft.report = "Keep this report"
        draft.finishCapture(try XCTUnwrap(draft.beginCapture()), png: pngFixture)
        draft.openEmail { _, completion in completion(true) }
        XCTAssertEqual(draft.status, .requested)
        XCTAssertEqual(draft.screenshot, pngFixture)
        XCTAssertEqual(draft.report, "Keep this report")
    }

    // MARK: - Actions - Fixtures

    private var pngFixture: Data {
        Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0])
    }

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
