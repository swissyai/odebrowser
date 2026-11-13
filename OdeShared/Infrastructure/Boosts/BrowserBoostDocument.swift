import Foundation

/// Where a page's engine runs Ode's Boost script: in every main-frame
/// document the page loads, in a script world the page cannot reach.
@MainActor
protocol BrowserBoostDocument: AnyObject {
    /// Starts the page's later main-frame documents with the Boost script, and
    /// with `styles`, CSS by site, where the engine can start a document with
    /// them; on an engine that cannot, the document asks for its CSS once it
    /// is ready. With `styles` empty and `keepsScript` false, later
    /// documents need no script, which the engine may then leave out.
    func prepare(styles: [String: String], keepsScript: Bool)
    /// Runs `body` with `arguments` bound as constants in the page's main
    /// document, in the Boost script's world.
    func run(_ body: String, arguments: [String: Any]) async
    /// Stops hearing the page's documents. The page is going away or moving
    /// to another engine.
    func close()
}

/// The Boost script on an engine that runs Ode's content scripts itself:
/// installed once, the first time a page needs it, after which each of the
/// page's main-frame documents runs it and asks for its CSS when ready.
@MainActor
final class BrowserScriptedBoostDocument: BrowserBoostDocument {
    // MARK: - Variables

    private weak var scripting: (any BrowserPageContentScripting)?
    private let receive: @MainActor (BrowserBoostPageMessage) -> Void
    private var isInstalled = false
    private var isClosed = false

    // MARK: - Initializers

    init(
        scripting: any BrowserPageContentScripting,
        receive: @escaping @MainActor (BrowserBoostPageMessage) -> Void
    ) {
        self.scripting = scripting
        self.receive = receive
    }

    // MARK: - Actions - Documents

    func prepare(styles: [String: String], keepsScript: Bool) {
        guard !isInstalled, !isClosed, !styles.isEmpty || keepsScript, let scripting else { return }
        isInstalled = scripting.install(
            BrowserContentScript(
                source: BrowserBoostContentBridge.documentStart(styles: nil),
                handlerName: BrowserBoostContentBridge.handlerName,
                mainFrameOnly: true)
        ) { [weak self] message in
            guard let self, !self.isClosed, message.frame.isMainFrame,
                let decoded = BrowserBoostPageMessage(body: message.body)
            else { return }
            self.receive(decoded)
        }
    }

    func run(_ body: String, arguments: [String: Any]) async {
        guard !isClosed else { return }
        _ = try? await scripting?.callAsyncJavaScriptInMainFrame(body, arguments: arguments)
    }

    func close() {
        isClosed = true
    }
}
