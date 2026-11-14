import Foundation
import Observation

/// One in-memory draft per app session. Nothing here reads browsing state or writes to disk.
@MainActor
@Observable
final class BrowserFeedbackDraft {
    // MARK: - Static Variables

    static let recipient = "feedback@odebrowser.com"
    static let applicationActionName = "feedback"
    /// A conservative encoded URL limit; larger reports remain available in full through Copy Text.
    static let maximumMailtoBytes = 8_000
    static let shared = BrowserFeedbackDraft(
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
        osVersion: ProcessInfo.processInfo.operatingSystemVersion
    )

    // MARK: - Types

    struct Status: Equatable, Sendable {
        static let opening = Status(message: String(localized: "Opening email…"))
        static let requested = Status(message: String(localized: "Email request handed off"))
        static let sending = Status(message: String(localized: "Sending…"))
        static let received = Status(message: String(localized: "Feedback received"))
        static let receivedWithEdits = Status(message: String(localized: "Feedback received. Your edits are kept."))
        static let screenshotSaved = Status(message: String(localized: "Screenshot saved"))
        static let screenshotSaveFailed = Status(message: String(localized: "Couldn’t save screenshot. Try again."))
        static let unavailable = Status(message: String(localized: "Couldn’t open email. Use Copy Text."))
        static let tooLong = Status(message: String(localized: "Report too long for an email link. Use Copy Text."))
        static let copied = Status(message: String(localized: "Copied"))
        static let copyFailed = Status(message: String(localized: "Couldn’t copy. Select the report text to copy it."))
        static let empty = Status(message: String(localized: "Write a report first."))

        let message: String
    }

    // MARK: - Variables

    var report = "" {
        didSet { if report != oldValue { retireReceipt() } }
    }
    var topic = "" {
        didSet { if topic != oldValue { retireReceipt() } }
    }
    var includesAppDetails = false {
        didSet { if includesAppDetails != oldValue { retireReceipt() } }
    }
    private(set) var status: Status?
    private(set) var isOpeningEmail = false
    private(set) var isSending = false
    private var attemptedSubmission: BrowserFeedbackSubmission?
    private var lastSendFailed = false
    private(set) var screenshot: Data? {
        didSet { if screenshot != oldValue { retireReceipt() } }
    }
    private(set) var captureMessage: String?
    private(set) var hasPreparedScreenshot = false
    private(set) var isCapturing = false
    private var captureID: UUID?
    let appDetails: String

    var hasReport: Bool {
        !report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRetrySending: Bool {
        guard lastSendFailed, let attemptedSubmission else { return false }
        return !isSending && submission(requestID: attemptedSubmission.requestID) == attemptedSubmission
    }

    var subject: String {
        // A topic is a single email header value, never an additional header.
        let singleLine = topic.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return singleLine.isEmpty ? String(localized: "Ode feedback") : String(localized: "Ode feedback: \(singleLine)")
    }

    var body: String {
        includesAppDetails ? report + "\n\n" + appDetails : report
    }

    var copyText: String {
        "\(Self.recipient)\n\(subject)\n\n\(body)"
    }

    var mailtoURL: URL? {
        guard hasReport else { return nil }
        // Encode every non-unreserved byte, including +, &, %, #, ? and line breaks.
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let subject = subject.addingPercentEncoding(withAllowedCharacters: unreserved),
            let body = body.addingPercentEncoding(withAllowedCharacters: unreserved)
        else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.recipient
        components.percentEncodedQuery = "subject=\(subject)&body=\(body)"
        guard let url = components.url, url.absoluteString.utf8.count <= Self.maximumMailtoBytes else { return nil }
        return url
    }

    // MARK: - Initializers

    init(version: String, build: String, osVersion: OperatingSystemVersion) {
        let os = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        appDetails = String(localized: "Ode \(version) (\(build))\nOS \(os)")
    }

    // MARK: - Actions - Presentation

    /// Entry points may seed a fresh draft, never replace a person's existing topic or report.
    func prepare(topic suggestedTopic: String?) {
        guard report.isEmpty, topic.isEmpty, let suggestedTopic else { return }
        topic = suggestedTopic
    }

    // MARK: - Actions - Capture

    /// A removed image stays removed on reopen. Only an explicit retake replaces it.
    func beginCapture(retake: Bool = false) -> UUID? {
        guard !isCapturing, retake || !hasPreparedScreenshot else { return nil }
        let id = UUID()
        captureID = id
        isCapturing = true
        hasPreparedScreenshot = true
        return id
    }

    func finishCapture(_ id: UUID, png: Data?, message: String? = nil) {
        guard captureID == id else { return }
        captureID = nil
        isCapturing = false
        // A failed retake must not destroy the previously reviewed image.
        if let png { screenshot = png }
        captureMessage =
            if png == nil, screenshot != nil, let message {
                message + " " + String(localized: "Previous screenshot kept.")
            } else {
                message
            }
    }

    /// An abandoned presentation cannot publish a late screenshot into a reopened draft.
    func cancelCapture(_ id: UUID) {
        guard captureID == id else { return }
        captureID = nil
        isCapturing = false
        hasPreparedScreenshot = screenshot != nil
    }

    func removeScreenshot() {
        captureID = nil
        isCapturing = false
        hasPreparedScreenshot = true
        screenshot = nil
        captureMessage = nil
    }

    // MARK: - Actions - Handoff

    /// A receipt clears only the exact reviewed snapshot, never edits made while sending.
    func send(using upload: (BrowserFeedbackSubmission) async throws -> Void) async {
        guard !isSending else { return }
        guard hasReport else {
            status = .empty
            return
        }
        let snapshot: BrowserFeedbackSubmission
        if let attemptedSubmission,
            submission(requestID: attemptedSubmission.requestID) == attemptedSubmission
        {
            snapshot = attemptedSubmission
        } else {
            snapshot = submission(requestID: UUID())
        }
        do {
            try snapshot.validate()
        } catch let failure as BrowserFeedbackSubmission.Failure {
            status = Status(message: failure.message)
            return
        } catch {
            status = Status(message: BrowserFeedbackSubmission.Failure.invalidReport.message)
            return
        }
        attemptedSubmission = snapshot
        isSending = true
        lastSendFailed = false
        status = .sending
        defer { isSending = false }
        do {
            try await upload(snapshot)
            if submission(requestID: snapshot.requestID) == snapshot {
                report = ""
                topic = ""
                includesAppDetails = false
                removeScreenshot()
                hasPreparedScreenshot = false
                status = .received
            } else {
                status = .receivedWithEdits
            }
            attemptedSubmission = nil
        } catch let failure as BrowserFeedbackSubmission.Failure {
            lastSendFailed = true
            status = Status(message: failure.message)
        } catch is CancellationError {
            lastSendFailed = true
            status = Status(message: BrowserFeedbackSubmission.Failure.cancelled.message)
        } catch {
            lastSendFailed = true
            status = Status(message: BrowserFeedbackSubmission.Failure.unavailable.message)
        }
    }

    private func retireReceipt() {
        if status == .received || status == .receivedWithEdits { status = nil }
    }

    private func submission(requestID: UUID) -> BrowserFeedbackSubmission {
        BrowserFeedbackSubmission(
            requestID: requestID, topic: topic, report: report,
            appDetails: includesAppDetails ? appDetails : nil,
            screenshot: screenshot.map { BrowserFeedbackSubmission.Screenshot(contentType: "image/png", base64: $0) })
    }

    func screenshotSaveFinished(succeeded: Bool) {
        status = succeeded ? .screenshotSaved : .screenshotSaveFailed
    }

    func openEmail(using open: (URL, @escaping @MainActor (Bool) -> Void) -> Void) {
        guard !isOpeningEmail else { return }
        guard hasReport else {
            status = .empty
            return
        }
        guard let url = mailtoURL else {
            status = .tooLong
            return
        }
        isOpeningEmail = true
        status = .opening
        open(url) { [weak self] accepted in
            guard let self else { return }
            isOpeningEmail = false
            if status == .opening {
                status = accepted ? .requested : .unavailable
            }
            // A handler opening is not a send receipt. Never clear or restore an earlier draft here.
        }
    }

    func copyReport(using copy: (String) -> Bool) {
        guard hasReport else {
            status = .empty
            return
        }
        status = copy(copyText) ? .copied : .copyFailed
    }
}
