import Foundation

/// One crash, hang or launch that never finished, as Ode keeps it on this Mac:
/// what happened, when, which build ran, and the technical details a fix
/// needs. Details hold only what a reader picked from the record: the kind of
/// failure, the stack of the thread that failed by image and offset, and how
/// long a hang lasted. A report never holds a page's address, title or
/// contents, and nothing leaves the Mac unless the person sends it.
struct BrowserCrashReport: Codable, Equatable, Identifiable, Sendable {
    // MARK: - Types

    enum Kind: String, Codable, Sendable {
        /// macOS recorded a crash of Ode or one of its helpers.
        case crash
        /// Ode's main thread stopped answering for seconds.
        case hang
        /// A launch never finished starting.
        case unfinishedStart
        /// A launch that had started ended without a quit the person asked for.
        case unexpectedQuit
    }

    /// Whether the report went anywhere. Only an uploader that confirmed the
    /// report arrived makes it `sent`.
    enum Delivery: Codable, Equatable, Sendable {
        case notSent
        case sent(Date)
        case failed(Date)
    }

    // MARK: - Variables

    /// Names the record it came from, so the same record is kept once.
    let id: String
    let kind: Kind
    let occurredAt: Date
    let build: String
    /// The technical one-line summary, such as the exception and the process.
    let summary: String
    let details: String
    var delivery: Delivery = .notSent

    /// The report's size on disk, roughly, for the store's cap.
    var bytes: Int { details.utf8.count + summary.utf8.count + 256 }

    // MARK: - Actions - Describing

    /// What happened, as the list and the notice say it.
    var title: String {
        switch kind {
        case .crash: String(localized: "Ode quit unexpectedly")
        case .hang: String(localized: "Ode stopped responding")
        case .unfinishedStart: String(localized: "Ode didn't finish starting")
        case .unexpectedQuit: String(localized: "Ode closed without being asked")
        }
    }

    var taken: String { occurredAt.formatted(date: .abbreviated, time: .shortened) }
}

/// The text a report becomes to be read, copied, saved or sent: a header of
/// facts, then its details with anything that could identify a page or the
/// person taken out once more, whatever reader made it.
enum BrowserCrashReportPayload {
    static func text(
        for report: BrowserCrashReport, osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) -> String {
        let header = [
            "Kind: \(report.kind.rawValue)",
            "When: \(report.occurredAt.ISO8601Format())",
            "Build: \(report.build)",
            "macOS: \(osVersion)",
            "Summary: \(report.summary)",
        ]
        return redact((header + ["", report.details]).joined(separator: "\n"))
    }

    /// `text` without web addresses, file and person paths, email addresses,
    /// memory addresses or runs of raw bytes.
    static func redact(_ text: String) -> String {
        var redacted = text
        for (pattern, replacement) in rules {
            redacted = redacted.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return redacted
    }

    private static let rules: [(String, String)] = [
        (#"[A-Za-z][A-Za-z0-9+.\-]*://[^\s"'<>]+"#, "<address removed>"),
        (#"(?:www\.)[A-Za-z0-9\-]+\.[A-Za-z]{2,}[^\s"'<>]*"#, "<address removed>"),
        (#"/Users/[^/\s"']+"#, "/Users/<user>"),
        (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "<email removed>"),
        (#"0x[0-9A-Fa-f]{5,}"#, "0x…"),
        (#"\b[0-9A-Fa-f]{32,}\b"#, "<bytes removed>"),
        (#"[A-Za-z0-9+/]{64,}={0,2}"#, "<bytes removed>"),
    ]
}
