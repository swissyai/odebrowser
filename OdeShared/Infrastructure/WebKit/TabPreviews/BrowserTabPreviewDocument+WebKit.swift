import Foundation
import WebKit

/// WebKit runs a preview's reader in a content world of its own, in the web
/// view's main frame.
extension BrowserTabPreviewDocument {
    static let webKitWorld = WKContentWorld.world(name: "Ode.TabPreview")

    init(webView: WKWebView) {
        self.init { [weak webView] body, arguments in
            try await webView?.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: Self.webKitWorld)
        }
    }
}
