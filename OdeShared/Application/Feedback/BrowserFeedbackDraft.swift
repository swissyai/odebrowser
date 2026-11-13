import Foundation
import Observation

/// One in-memory draft per app session. Nothing here reads browsing state or writes to disk.
@MainActor
@Observable
final class BrowserFeedbackDraft {
    // MARK: - Static Variables

    static let recipient = "feedback@odebrowser.com"
    /// A conservative encoded URL limit; larger reports remain available in full through Copy Report.
    static let maximumMailtoBytes = 8_000
    static let shared = BrowserFeedbackDraft(
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
        osVersion: ProcessInfo.processInfo.operatingSystemVersion
    )

    // MARK: - Types

    struct Status: Equatable, Sendable {
        static let opening = Status(message: String(localized: "Opening email…"))
        static let opened = Status(message: String(localized: "Email app opened"))
        static let unavailable = Status(message: String(localized: "Couldn’t open email. Use Copy Report."))
        static let tooLong = Status(message: String(localized: "Report too long for an email link. Use Copy Report."))
        static let copied = Status(message: String(localized: "Copied"))
        static let copyFailed = Status(message: String(localized: "Couldn’t copy. Select the report text to copy it."))
        static let empty = Status(message: String(localized: "Write a report first."))

        let message: String
    }

    // MARK: - Variables

    var report = ""
    var topic = ""
    var includesAppDetails = false
    private(set) var status: Status?
    private(set) var isOpeningEmail = false
    let appDetails: String

    var hasReport: Bool {
        !report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    // MARK: - Actions - Handoff

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
                status = accepted ? .opened : .unavailable
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
