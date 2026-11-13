import WebKit

/// The Boost script on a WebKit page: a user script in Ode's own content
/// world that every main-frame document starts with, holding the CSS of each
/// boosted site so a document wears its site's from its first paint. It is
/// replaced whenever that CSS changes, and left out while no site has any.
@MainActor
final class BrowserWebKitBoostDocument: BrowserBoostDocument {
    // MARK: - Static Variables

    static let world = WKContentWorld.world(name: "com.odebrowser.ode.boosts")

    // MARK: - Variables

    private weak var webView: WKWebView?
    private var script: WKUserScript?
    private var isListening = false

    // MARK: - Initializers

    /// The Boost script on `webView`, whose user content controller the page
    /// owns rather than shares with an opener.
    init(webView: WKWebView, receive: @escaping @MainActor (BrowserBoostPageMessage) -> Void) {
        self.webView = webView
        webView.configuration.userContentController.add(
            BrowserScriptMessageProxy { message in
                guard message.frameInfo.isMainFrame, let decoded = BrowserBoostPageMessage(body: message.body) else {
                    return
                }
                receive(decoded)
            },
            contentWorld: Self.world,
            name: BrowserBoostContentBridge.handlerName
        )
        isListening = true
    }

    // MARK: - Actions - Documents

    func prepare(styles: [String: String], keepsScript: Bool) {
        guard let controller = webView?.configuration.userContentController else { return }
        let next =
            styles.isEmpty && !keepsScript
            ? nil
            : WKUserScript(
                source: BrowserBoostContentBridge.documentStart(styles: styles), injectionTime: .atDocumentStart,
                forMainFrameOnly: true, in: Self.world)
        guard script != nil || next != nil else { return }
        // WebKit removes user scripts only all at once, so the page's other
        // bridges go back in as they were.
        let others = controller.userScripts.filter { $0 !== script }
        controller.removeAllUserScripts()
        others.forEach(controller.addUserScript)
        if let next { controller.addUserScript(next) }
        script = next
    }

    func run(_ body: String, arguments: [String: Any]) async {
        _ = try? await webView?.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: Self.world)
    }

    func close() {
        prepare(styles: [:], keepsScript: false)
        if isListening {
            webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: BrowserBoostContentBridge.handlerName, contentWorld: Self.world)
            isListening = false
        }
        webView = nil
    }
}
