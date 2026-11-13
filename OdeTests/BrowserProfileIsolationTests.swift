import WebKit
import XCTest

@testable import Ode

@MainActor
final class BrowserProfileIsolationTests: XCTestCase {
    func testPrivateStoresShareNothingAndCannotBeRehydrated() async throws {
        let storeA = WKWebsiteDataStore.nonPersistent()
        let storeB = WKWebsiteDataStore.nonPersistent()
        let cookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "private.crest.test",
                .path: "/",
                .name: "private-session",
                .value: "space-a",
                .secure: "TRUE",
            ])
        )

        await set(cookie, in: storeA.httpCookieStore)

        let cookiesA = await cookies(in: storeA.httpCookieStore)
        let cookiesB = await cookies(in: storeB.httpCookieStore)
        let replacementStore = WKWebsiteDataStore.nonPersistent()
        let replacementCookies = await cookies(in: replacementStore.httpCookieStore)

        XCTAssertFalse(storeA.isPersistent)
        XCTAssertNil(storeA.identifier)
        XCTAssertEqual(cookiesA.first(where: { $0.name == cookie.name })?.value, "space-a")
        XCTAssertNil(cookiesB.first(where: { $0.name == cookie.name }))
        XCTAssertNil(replacementCookies.first(where: { $0.name == cookie.name }))

        await delete(cookie, from: storeA.httpCookieStore)
    }

    private func set(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func cookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func delete(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) {
                continuation.resume()
            }
        }
    }
}
