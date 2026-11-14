import Foundation
import WebKit

/// Draws SVG site icons as PNG for tabs whose page never loaded, in a web view
/// of its own that no window shows. The SVG is drawn as an image, which can
/// run no script and fetch nothing; the view keeps no website data and runs
/// no page script, and it goes once it has been idle a while, taking its web
/// content process with it.
@MainActor
final class BrowserFaviconSVGRasterizer: NSObject {
    // MARK: - Static Variables

    static let shared = BrowserFaviconSVGRasterizer()
    private static let idleLifetime: Duration = .seconds(60)
    private static let drawingTimeout: Duration = .seconds(5)
    private static let maximumPixelSize = 512
    private static let pngPrefix = "data:image/png;base64,"
    private static let script = #"""
        const image = new Image();
        image.src = `data:image/svg+xml;base64,${svgBase64}`;
        await image.decode();
        const sourceWidth = Math.max(1, image.naturalWidth || pixelSize);
        const sourceHeight = Math.max(1, image.naturalHeight || pixelSize);
        const scale = pixelSize / Math.max(sourceWidth, sourceHeight);
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(sourceWidth * scale));
        canvas.height = Math.max(1, Math.round(sourceHeight * scale));
        // This canvas is immediately read back as PNG rather than displayed.
        const context = canvas.getContext('2d', { willReadFrequently: true });
        if (!context) throw new Error('Canvas 2D context is unavailable');
        context.drawImage(image, 0, 0, canvas.width, canvas.height);
        if (tint) {
            context.globalCompositeOperation = 'source-in';
            context.fillStyle = tint;
            context.fillRect(0, 0, canvas.width, canvas.height);
        }
        return canvas.toDataURL('image/png');
        """#

    // MARK: - Types

    /// Lets the first of two racing answers through.
    private final class Once {
        private var isDone = false

        func finish(_ answer: () -> Void) {
            guard !isDone else { return }
            isDone = true
            answer()
        }
    }

    // MARK: - Variables

    private var webView: WKWebView?
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var isLoading = false
    private var idleTask: Task<Void, Never>?

    // MARK: - Actions - Drawing

    /// `svg` drawn as a PNG whose longer side is `pixelSize`, filled with
    /// `tint` where the icon is a one-color silhouette, or nil when it cannot
    /// be drawn in time.
    nonisolated static func png(from svg: Data, pixelSize: Int, tint: String?) async -> Data? {
        await shared.draw(svg, pixelSize: pixelSize, tint: tint)
    }

    private func draw(_ svg: Data, pixelSize: Int, tint: String?) async -> Data? {
        guard !svg.isEmpty, svg.count <= BrowserFaviconCapture.maximumByteCount * 2 else { return nil }
        idleTask?.cancel()
        defer { scheduleTeardown() }
        let webView = await loadedWebView()
        let arguments: [String: Any] = [
            "svgBase64": svg.base64EncodedString(),
            "pixelSize": min(max(pixelSize, 16), Self.maximumPixelSize),
            "tint": tint ?? "",
        ]
        let drawn: String? = await withCheckedContinuation { continuation in
            let once = Once()
            Task { @MainActor in
                let value = try? await webView.callAsyncJavaScript(
                    Self.script, arguments: arguments, in: nil, contentWorld: .defaultClient)
                once.finish { continuation.resume(returning: value as? String) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: Self.drawingTimeout)
                once.finish { continuation.resume(returning: nil) }
            }
        }
        guard let drawn, drawn.hasPrefix(Self.pngPrefix) else { return nil }
        return Data(base64Encoded: String(drawn.dropFirst(Self.pngPrefix.count)))
    }

    /// The drawing view, with its blank document loaded; a view whose load
    /// failed still draws in its first, empty document.
    private func loadedWebView() async -> WKWebView {
        if let webView, !isLoading { return webView }
        let webView = self.webView ?? makeWebView()
        if self.webView == nil {
            self.webView = webView
            isLoading = true
            webView.loadHTMLString("<!doctype html><meta charset=\"utf-8\">", baseURL: nil)
        }
        await withCheckedContinuation { loadWaiters.append($0) }
        return webView
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        webView.navigationDelegate = self
        return webView
    }

    // MARK: - Actions - Lifetime

    private func finishLoading() {
        isLoading = false
        let waiters = loadWaiters
        loadWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    private func scheduleTeardown() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleLifetime)
            guard !Task.isCancelled else { return }
            self?.tearDown()
        }
    }

    private func tearDown() {
        webView?.navigationDelegate = nil
        webView = nil
        finishLoading()
    }
}

extension BrowserFaviconSVGRasterizer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        finishLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard webView === self.webView else { return }
        finishLoading()
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        guard webView === self.webView else { return }
        finishLoading()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        tearDown()
    }
}
