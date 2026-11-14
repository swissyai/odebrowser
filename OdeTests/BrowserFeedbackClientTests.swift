import Foundation
import XCTest

@testable import Ode

/// The real HTTP stack talks only to a local fixture; no test sends a report to Ode.
@MainActor
final class BrowserFeedbackClientTests: XCTestCase {
    func testRequestContainsOnlyExplicitReportFieldsAndNoAmbientCredentials() throws {
        let submission = makeSubmission()
        let request = try BrowserFeedbackClient().request(for: submission)
        XCTAssertEqual(request.url?.absoluteString, "https://odebrowser.com/api/feedback")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let data = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["requestID", "topic", "report", "screenshot"])
        XCTAssertEqual(payload["report"] as? String, submission.report)
        XCTAssertEqual(try submission.encoded(), data, "An exact retry has stable bytes as well as a stable request ID")
        let screenshot = try XCTUnwrap(payload["screenshot"] as? [String: String])
        XCTAssertEqual(Set(screenshot.keys), ["contentType", "base64"])
        XCTAssertEqual(screenshot["contentType"], "image/png")
        XCTAssertEqual(screenshot["base64"].flatMap { Data(base64Encoded: $0) }, submission.screenshot?.base64)
        let configuration = BrowserFeedbackClient.sessionConfiguration
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertFalse(configuration.httpShouldSetCookies)
    }

    func testOnlyMatchingAcceptedReceiptSucceedsAndFailuresKeepDraft() async throws {
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        let restore = installFixture(server)
        defer {
            restore()
            server.stop()
        }
        let submission = makeSubmission()
        let accepted =
            "{\"requestID\":\"\(submission.requestID)\",\"messageId\":\"fixture-receipt\",\"status\":\"accepted\"}"
        let cases: [(String, String, BrowserFeedbackSubmission.Failure?)] = [
            ("503 Service Unavailable", "{}", .unconfirmed),
            ("503 Service Unavailable", "{\"error\":{\"code\":\"unavailable\"}}", .unavailable),
            ("503 Service Unavailable", "{\"error\":{\"code\":\"send_failed\"}}", .unconfirmed),
            ("429 Too Many Requests", "{\"error\":{\"code\":\"rate_limited\"}}", .rateLimited),
            ("413 Content Too Large", "{\"error\":{\"code\":\"too_large\"}}", .requestTooLarge),
            ("400 Bad Request", "{\"error\":{\"code\":\"invalid_screenshot\"}}", .invalidScreenshot),
            ("400 Bad Request", "{\"error\":{\"code\":\"invalid_request\"}}", .invalidReport),
            ("200 OK", accepted, .unconfirmed),
            ("202 Accepted", "{broken", .unconfirmed),
            ("202 Accepted", accepted.replacingOccurrences(of: "fixture-receipt", with: ""), .unconfirmed),
            (
                "202 Accepted",
                accepted.replacingOccurrences(of: submission.requestID.uuidString, with: UUID().uuidString),
                .unconfirmed
            ),
            ("202 Accepted", accepted.replacingOccurrences(of: "accepted", with: "queued"), .unconfirmed),
            ("202 Accepted", accepted, nil),
        ]
        for (status, body, expected) in cases {
            server.overrideResponse = { _ in (status, "Content-Type: application/json\r\n", Data(body.utf8)) }
            do {
                try await BrowserFeedbackClient.shared.send(submission)
                XCTAssertNil(expected, "Unexpected success for \(status)")
            } catch let failure as BrowserFeedbackSubmission.Failure {
                XCTAssertEqual(failure, expected)
            }
        }
        XCTAssertEqual(server.requests.count, cases.count)
        XCTAssertTrue(server.requests.allSatisfy { $0.path == "/odebrowser.com/api/feedback" })
        XCTAssertTrue(server.requests.allSatisfy { $0.headers["authorization"] == nil && $0.headers["cookie"] == nil })
    }

    func testRedirectCannotCarryReportToAnotherDestination() async throws {
        let source = try BrowserPrivacyHTTPServer()
        let destination = try BrowserPrivacyHTTPServer()
        try await destination.start()
        let target = destination.url(host: "127.0.0.1", path: "/stolen-report").absoluteString
        source.overrideResponse = { _ in ("307 Temporary Redirect", "Location: \(target)\r\n", Data()) }
        try await source.start()
        let restore = installFixture(source)
        defer {
            restore()
            source.stop()
            destination.stop()
        }
        do {
            try await BrowserFeedbackClient.shared.send(makeSubmission())
            XCTFail("A redirect was accepted as a receipt")
        } catch let failure as BrowserFeedbackSubmission.Failure {
            XCTAssertEqual(failure, .unconfirmed)
        }
        XCTAssertEqual(source.requests.count, 1)
        XCTAssertTrue(destination.requests.isEmpty)
    }

    func testPayloadCapsRejectOversizedOrNonPNGAttachmentsBeforeTransport() throws {
        let submission = makeSubmission()
        let tooLarge = BrowserFeedbackSubmission(
            requestID: submission.requestID, topic: "", report: "Keep this report", appDetails: nil,
            screenshot: .init(contentType: "image/png", base64: Data(repeating: 0, count: 8 * 1024 * 1024 + 1)))
        XCTAssertThrowsError(try BrowserFeedbackClient().request(for: tooLarge)) { error in
            XCTAssertEqual(error as? BrowserFeedbackSubmission.Failure, .screenshotTooLarge)
        }
        let invalid = BrowserFeedbackSubmission(
            requestID: submission.requestID, topic: "", report: "Keep this report", appDetails: nil,
            screenshot: .init(contentType: "image/png", base64: Data("not a PNG".utf8)))
        XCTAssertThrowsError(try invalid.encoded()) { error in
            XCTAssertEqual(error as? BrowserFeedbackSubmission.Failure, .invalidScreenshot)
        }
    }

    private func makeSubmission() -> BrowserFeedbackSubmission {
        BrowserFeedbackSubmission(
            requestID: UUID(), topic: "A report", report: "The reviewed report", appDetails: nil,
            screenshot: .init(contentType: "image/png", base64: Data([137, 80, 78, 71, 13, 10, 26, 10])))
    }

    private func installFixture(_ server: BrowserPrivacyHTTPServer) -> () -> Void {
        let previous = ProcessInfo.processInfo.environment[BrowserNetworkFixture.environmentKey]
        setenv(BrowserNetworkFixture.environmentKey, "http://127.0.0.1:\(server.port)", 1)
        return {
            if let previous {
                setenv(BrowserNetworkFixture.environmentKey, previous, 1)
            } else {
                unsetenv(BrowserNetworkFixture.environmentKey)
            }
        }
    }
}
