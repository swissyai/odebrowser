import Foundation

/// Exactly the report a person reviewed. No browsing state is consulted while preparing it.
struct BrowserFeedbackSubmission: Encodable, Equatable, Sendable {
    // MARK: - Static Variables

    static let maximumScreenshotBytes = 8 * 1024 * 1024
    static let maximumRequestBytes = 12 * 1024 * 1024

    // MARK: - Types

    struct Screenshot: Encodable, Equatable, Sendable {
        let contentType: String
        let base64: Data
    }

    struct Failure: Error, Equatable, Sendable {
        static let invalidReport = Failure(message: String(localized: "Check your report and try again."))
        static let reportTooLong = Failure(message: String(localized: "Report is too long. Shorten it or Copy Text."))
        static let topicTooLong = Failure(message: String(localized: "Topic is too long. Shorten it."))
        static let screenshotTooLarge = Failure(
            message: String(localized: "Screenshot is too large. Remove it or retake."))
        static let invalidScreenshot = Failure(
            message: String(localized: "Couldn’t prepare the screenshot. Remove it or retake."))
        static let requestTooLarge = Failure(
            message: String(localized: "Report is too large. Remove the screenshot or Copy Text."))
        static let unavailable = Failure(message: String(localized: "Couldn’t send. Retry or Copy Text."))
        static let offline = Failure(message: String(localized: "You’re offline. Retry when connected."))
        static let rateLimited = Failure(message: String(localized: "Too many attempts. Try again later."))
        static let unconfirmed = Failure(
            message: String(localized: "Couldn’t confirm receipt. Retrying may send a duplicate."))
        static let cancelled = Failure(message: String(localized: "Sending stopped. Retrying may send a duplicate."))

        let message: String
    }

    // MARK: - Variables

    let requestID: UUID
    let topic: String
    let report: String
    let appDetails: String?
    let screenshot: Screenshot?

    // MARK: - Actions - Validation

    func validate() throws {
        guard !report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidReport }
        guard topic.utf16.count <= 160 else { throw Failure.topicTooLong }
        guard report.utf16.count <= 20_000 else { throw Failure.reportTooLong }
        guard appDetails?.utf16.count ?? 0 <= 512 else { throw Failure.invalidReport }
        if let screenshot {
            guard screenshot.base64.count <= Self.maximumScreenshotBytes else { throw Failure.screenshotTooLarge }
            guard screenshot.contentType == "image/png",
                screenshot.base64.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
            else { throw Failure.invalidScreenshot }
        }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumRequestBytes else { throw Failure.requestTooLarge }
        return data
    }
}
