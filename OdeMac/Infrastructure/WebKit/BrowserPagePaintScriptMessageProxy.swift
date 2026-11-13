import Foundation
import WebKit

/// Forwards the paint bridge's messages without becoming a retain cycle: the
/// page owns the content controller, which owns its handlers, so the page
/// captures itself weakly in `receive`.
@MainActor
final class BrowserPagePaintScriptMessageProxy: NSObject, WKScriptMessageHandler {
    // MARK: - Variables

    private weak var webView: WKWebView?
    private let receive: @MainActor (Any) -> Void

    // MARK: - Initializers

    init(webView: WKWebView, receive: @escaping @MainActor (Any) -> Void) {
        self.webView = webView
        self.receive = receive
    }

    // MARK: - Actions - Messages

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame, message.webView === webView else { return }
        receive(message.body)
    }
}

extension BrowserPagePaintBridge {
    /// The bridge's own script world on WebKit, apart from the page's.
    @MainActor static let contentWorld = WKContentWorld.world(name: "com.odebrowser.page-paint")

    /// Runs the bridge in every main-frame document `controller` loads,
    /// handing each report to `receive`.
    @MainActor
    static func install(
        in webView: WKWebView,
        receive: @escaping @MainActor (Any) -> Void
    ) -> BrowserPagePaintScriptMessageProxy {
        let controller = webView.configuration.userContentController
        let proxy = BrowserPagePaintScriptMessageProxy(webView: webView, receive: receive)
        controller.add(proxy, contentWorld: contentWorld, name: messageHandlerName)
        controller.addUserScript(
            WKUserScript(
                source: script.source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: contentWorld))
        return proxy
    }
}
