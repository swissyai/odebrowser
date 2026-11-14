import Foundation

/// An explicit report upload to Ode. Browsing cookies, credentials and caches never join the request.
struct BrowserFeedbackClient: Sendable {
    // MARK: - Static Variables

    static let shared = BrowserFeedbackClient()
    private static let endpoint = URL(string: "https://odebrowser.com/api/feedback")
    static var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return configuration
    }

    private static let defaultSession = URLSession(configuration: sessionConfiguration)

    // MARK: - Types

    private struct Receipt: Decodable {
        enum Status: String, Decodable {
            case accepted
        }

        let requestID: UUID
        let messageId: String
        let status: Status
    }

    private struct Rejection: Decodable {
        enum Code: String, Decodable {
            case invalidRequest = "invalid_request"
            case invalidScreenshot = "invalid_screenshot"
            case tooLarge = "too_large"
            case invalidContentType = "invalid_content_type"
            case uploadTimeout = "upload_timeout"
            case rateLimited = "rate_limited"
            case busy
            case requestChanged = "request_changed"
            case unavailable
            case sendFailed = "send_failed"
            case methodNotAllowed = "method_not_allowed"
        }

        struct Detail: Decodable {
            let code: Code
        }

        let requestID: UUID?
        let error: Detail
    }

    // MARK: - Variables

    private let session: URLSession

    // MARK: - Initializers

    init(session: URLSession? = nil) {
        self.session = session ?? Self.defaultSession
    }

    // MARK: - Actions - Sending

    func request(for submission: BrowserFeedbackSubmission) throws -> URLRequest {
        guard let endpoint = Self.endpoint else { throw BrowserFeedbackSubmission.Failure.unavailable }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try submission.encoded()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Ode Feedback", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        return request
    }

    func send(_ submission: BrowserFeedbackSubmission) async throws {
        var request = try request(for: submission)
        guard let endpoint = request.url, let routed = BrowserNetworkFixture.routed(endpoint) else {
            throw BrowserFeedbackSubmission.Failure.unavailable
        }
        request.url = routed
        let data: Data
        let response: URLResponse
        do {
            // This existing boundary refuses every redirect, including same-host redirects.
            (data, response) = try await session.data(for: request, delegate: BrowserNetworkFixture.redirectGuard)
        } catch let error as URLError {
            if error.code == .notConnectedToInternet { throw BrowserFeedbackSubmission.Failure.offline }
            if error.code == .cancelled { throw CancellationError() }
            throw BrowserFeedbackSubmission.Failure.unconfirmed
        } catch {
            throw BrowserFeedbackSubmission.Failure.unconfirmed
        }
        guard let response = response as? HTTPURLResponse else {
            throw BrowserFeedbackSubmission.Failure.unconfirmed
        }
        guard response.statusCode == 202 else {
            throw rejection(data, requestID: submission.requestID)
        }
        guard data.count <= 4096, let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
            receipt.requestID == submission.requestID,
            !receipt.messageId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw BrowserFeedbackSubmission.Failure.unconfirmed }
    }

    /// Only known, bounded server codes distinguish a definite rejection from an uncertain send.
    private func rejection(_ data: Data, requestID: UUID) -> BrowserFeedbackSubmission.Failure {
        guard data.count <= 4096, let rejection = try? JSONDecoder().decode(Rejection.self, from: data),
            rejection.requestID == nil || rejection.requestID == requestID
        else { return .unconfirmed }
        switch rejection.error.code {
        case .invalidRequest, .invalidContentType:
            return .invalidReport
        case .invalidScreenshot:
            return .invalidScreenshot
        case .tooLarge:
            return .requestTooLarge
        case .rateLimited, .busy:
            return .rateLimited
        case .unavailable, .uploadTimeout, .methodNotAllowed:
            return .unavailable
        case .sendFailed, .requestChanged:
            return .unconfirmed
        }
    }
}
