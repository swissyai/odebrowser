import WebKit
import XCTest

@testable import OdeMobile

@MainActor
final class MobileBrowserPageConfigurationTests: XCTestCase {
    func testContextPreviewKeepsTheSourceProfileWithoutChangingItsPreferencesOrPage() throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let source = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        let url = try XCTUnwrap(URL(string: "https://preview.crest.test"))
        let preview = MobileBrowserLinkPreviewController(url: url, source: source, isCurrent: { true })

        XCTAssertTrue(preview.webView.configuration.websiteDataStore === source.configuration.websiteDataStore)
        XCTAssertFalse(preview.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(
            preview.webView.configuration.userContentController === source.configuration.userContentController)
        XCTAssertFalse(preview.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertTrue(source.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertNil(source.url)
    }

    /// Initial navigation can precede layout. Narrow and unhosted pages use
    /// mobile content, while an explicit desktop request survives resizing.
    func testNavigationChoosesReadableContentBeforeLayoutAndKeepsTheDesktopChoice() async throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:9/content-mode"))
        for width: CGFloat in [0, 402, 538] {
            for requestsDesktop in [false, true] {
                let space = makeSpace(index: 4)
                let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
                let page = try openPage(in: space, through: browser)
                defer { page.release(keepingState: false) }
                if requestsDesktop { page.togglePreferredContentMode() }
                page.webView.frame = CGRect(x: 0, y: 0, width: width, height: 800)

                let navigation = try XCTUnwrap(
                    page.webView.loadSimulatedRequest(
                        URLRequest(url: url), responseHTML: "<title>Local fixture</title><p>Reading</p>"))
                for _ in 0..<200 where page.completedNavigationCount == 0 {
                    try await Task.sleep(for: .milliseconds(20))
                }

                XCTAssertGreaterThan(page.completedNavigationCount, 0)
                XCTAssertEqual(
                    navigation.effectiveContentMode, requestsDesktop ? .desktop : .mobile,
                    "Initial width: \(width), explicit desktop: \(requestsDesktop)")
                if requestsDesktop {
                    page.webView.frame.size.width = 834
                    let resizedNavigation = try XCTUnwrap(
                        page.webView.loadSimulatedRequest(
                            URLRequest(url: url), responseHTML: "<title>Local fixture</title><p>Reading</p>"))
                    for _ in 0..<200 where page.completedNavigationCount < 2 {
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    XCTAssertGreaterThan(page.completedNavigationCount, 1)
                    XCTAssertEqual(resizedNavigation.effectiveContentMode, .desktop)
                }
                withExtendedLifetime(browser) {}
            }
        }
    }

    /// Opens the page for `space`'s first tab through `browser`'s core, as a
    /// page store opens one. Keep `browser` alive while the page is in use.
    private func openPage(in space: SpaceState.Seed, through browser: BrowserStore) throws -> MobileBrowserPage {
        let tab = try XCTUnwrap(space.tabs.first)
        return try XCTUnwrap(
            browser.openWebKitPage(in: space.id, for: tab.id).map { opened in
                MobileBrowserPage(
                    corePage: opened.core,
                    webKitPage: opened.webKit,
                    tab: browser.pageTab(tab.id, in: space.id),
                    space: browser.hostedSpace(space.id)
                )
            }
        )
    }

    private func makeSpace(index: Int) -> SpaceState.Seed {
        let tab = TabState.Seed.startPage(
            id: UUID.fixed(index * 10 + 1),
            placement: .current
        )
        return SpaceState.Seed(
            id: UUID.fixed(index * 10 + 2),
            profileID: UUID.fixed(index * 10 + 3),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
    }
}
