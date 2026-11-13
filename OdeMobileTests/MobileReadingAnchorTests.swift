import UIKit
import WebKit
import XCTest

@testable import OdeMobile

/// A page keeps what the person was reading at the top of the window when the
/// window changes width, as folding, unfolding or turning a phone does.
@MainActor
final class MobileReadingAnchorTests: XCTestCase {
    func testWideningAndNarrowingKeepTheParagraphBeingReadAtTheTop() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        MobileReadingAnchorContentBridge.install(in: configuration.userContentController)
        let window = try makeWindow()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 440, height: 800), configuration: configuration)
        window.addSubview(webView)
        defer { window.isHidden = true }

        webView.loadHTMLString(Self.article, baseURL: nil)
        try await waitUntil {
            await self.evaluate("document.readyState === 'complete' && !!document.getElementById('p59')", in: webView)
                as? Bool == true && webView.scrollView.contentSize.height > 2_000
        }
        let narrow = await offsetTop(of: "p30", in: webView)
        let narrowOffset = try XCTUnwrap(narrow)
        webView.scrollView.setContentOffset(
            CGPoint(x: 0, y: narrowOffset - webView.scrollView.adjustedContentInset.top), animated: false)
        // The person reads for a moment, so the page notes where they are.
        try await Task.sleep(for: .milliseconds(400))
        try await assertParagraphIsAtTop("p30", in: webView)

        webView.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
        try await waitUntil { await self.evaluate("innerWidth", in: webView) as? Double == 956 }
        try await waitForFrames(in: webView)
        let wide = await offsetTop(of: "p30", in: webView)
        let wideOffset = try XCTUnwrap(wide)
        // The wider column moves the paragraph up the document, so a kept
        // scroll offset alone would land far past it.
        XCTAssertGreaterThan(narrowOffset - wideOffset, 2_000)
        try await assertParagraphIsAtTop("p30", in: webView)

        try await Task.sleep(for: .milliseconds(400))
        webView.frame = CGRect(x: 0, y: 0, width: 440, height: 800)
        try await waitUntil { await self.evaluate("innerWidth", in: webView) as? Double == 440 }
        try await waitForFrames(in: webView)
        try await assertParagraphIsAtTop("p30", in: webView)
    }

    // MARK: - Support

    private static let article: String = {
        let sentence = "Folding the phone changes how wide this column is, so every line above wraps again. "
        let paragraphs = (0..<60).map { index in
            "<p id=\"p\(index)\">\(index). \(String(repeating: sentence, count: 6))</p>"
        }
        return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <style>body { margin: 0; font: 17px/1.4 -apple-system; -webkit-text-size-adjust: 100%; } p { margin: 0 0 12px; padding: 0 16px; }</style>
            </head><body>\(paragraphs.joined())</body></html>
            """
    }()

    private func assertParagraphIsAtTop(
        _ id: String,
        in webView: WKWebView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let value = await evaluate("document.getElementById('\(id)').getBoundingClientRect().top", in: webView)
        let top = try XCTUnwrap(value as? Double, file: file, line: line)
        XCTAssertEqual(top, 0, accuracy: 12, file: file, line: line)
    }

    private func offsetTop(of id: String, in webView: WKWebView) async -> Double? {
        await evaluate("document.getElementById('\(id)').offsetTop", in: webView) as? Double
    }

    private func evaluate(_ script: String, in webView: WKWebView) async -> Any? {
        try? await webView.evaluateJavaScript(script)
    }

    /// Lets the page run a few animation frames, where the anchor notes and
    /// restores its place.
    private func waitForFrames(in webView: WKWebView) async throws {
        _ = try await webView.callAsyncJavaScript(
            """
            await new Promise(resolve => {
              let frames = 0;
              const step = () => (++frames >= 4 ? resolve() : requestAnimationFrame(step));
              requestAnimationFrame(step);
            });
            return true;
            """,
            contentWorld: .page)
    }

    private func makeWindow() throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        window.isHidden = false
        return window
    }
}
