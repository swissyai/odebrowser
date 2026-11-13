import XCTest

@testable import Ode

/// What agents read of a tab's network requests: never the credentials
/// that headers and addresses carry.
@MainActor
final class BrowserAgentNetworkRequestTests: XCTestCase {
    func testCredentialsInHeadersAndAddressesAreHidden() {
        let request = PageNetworkRequest(
            sequence: 7,
            url:
                "https://person:hunter2@api.example.com/v1/items?id=7&access_token=abc123&key=K9#state=x&id_token=jwt42",
            method: "GET", resourceType: "fetch", status: 200, mimeType: "application/json",
            requestHeaders: [
                PageHeader(name: "Authorization", value: "Bearer abc123"),
                PageHeader(name: "X-CSRFToken", value: "csrf42"),
                PageHeader(name: "X-Amz-Security-Token", value: "amz42"),
                PageHeader(name: "Accept", value: "application/json"),
            ],
            responseHeaders: [PageHeader(name: "Set-Cookie", value: "sid=s42")], started: Date(), duration: 12,
            bytes: 100, failure: nil)

        let listing = BrowserMacAgents.RequestListing(request)
        let detail = BrowserMacAgents.RequestDetail(request)

        for address in [listing.url, detail.url] {
            for secret in ["hunter2", "person", "abc123", "K9", "jwt42"] {
                XCTAssertFalse(address.contains(secret), "\(address) shows \(secret).")
            }
            XCTAssertTrue(address.contains("id=7") && address.contains("state=x"), address)
        }
        XCTAssertEqual(detail.requestHeaders?["Accept"], "application/json")
        for (name, value) in (detail.requestHeaders ?? [:]).merging(
            detail.responseHeaders ?? [:], uniquingKeysWith: { a, _ in a })
        where name != "Accept" {
            XCTAssertEqual(value, BrowserMacAgents.RequestListing.hidden, "\(name) is shown.")
        }
    }

    func testAnAddressWithoutCredentialsIsUnchanged() {
        let address = "https://example.com/search?q=a%20b&page=2#results"

        XCTAssertEqual(BrowserMacAgents.RequestListing.shown(address), address)
    }
}
