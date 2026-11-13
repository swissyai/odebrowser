import CoreFoundation
import Foundation
import WebKit

@MainActor
final class BrowserTypedTextScriptMessageProxy: NSObject, WKScriptMessageHandler {
    // MARK: - Variables

    private let receive: @MainActor (WKScriptMessage) -> Void

    // MARK: - Initializers

    init(receive: @escaping @MainActor (WKScriptMessage) -> Void) {
        self.receive = receive
    }

    // MARK: - Actions - Messages

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == BrowserTypedTextContentBridge.messageHandlerName else { return }
        receive(message)
    }
}

/// Reports only whether trusted editing occurred, never field values, text,
/// selectors or origins. The script runs in an isolated world in every frame.
/// Password fields are excluded. No draft content is copied, logged or saved.
///
/// A submit, reset, empty field or removed editor does not prove that a site
/// saved a draft. Both the document and its native page conservatively latch
/// the signal until they are released. A frame's startup report cannot clear
/// another frame's edit. This protects idle residency, not crash recovery or
/// restoration of text after an engine change or app restart.
@MainActor
enum BrowserTypedTextContentBridge {
    // MARK: - Static Variables

    static let messageHandlerName = "odeTypedText"
    static let contentWorld = WKContentWorld.world(name: "com.odebrowser.ode.typed-text")

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__odeTypedTextBridge) return;
          globalThis.__odeTypedTextBridge = true;

          const post = (holds) => {
            try { globalThis.webkit.messageHandlers.odeTypedText.postMessage(holds); } catch (_) {}
          };
          const textTypes = new Set(["", "text", "search", "email", "url", "tel", "number"]);
          const isEditor = (node) => {
            if (node instanceof HTMLTextAreaElement) return true;
            if (node instanceof HTMLInputElement) return textTypes.has(node.type);
            const element = node instanceof Element ? node : node?.parentElement;
            return !!element && (element.isContentEditable || document.designMode === "on");
          };
          let holds = false;
          const edited = (event) => {
            if (holds || !event.isTrusted || !isEditor(event.composedPath()[0])) return;
            holds = true;
            post(true);
          };
          // Report without a debounce. Beforeinput is conservative even when
          // a site cancels it; input also covers editing paths without it.
          globalThis.addEventListener("beforeinput", edited, { capture: true, passive: true });
          globalThis.addEventListener("input", edited, { capture: true, passive: true });
          globalThis.addEventListener("pageshow", (event) => { if (event.persisted) post(holds); });
          post(false);
        })();
        """#

    // MARK: - Actions - Installation

    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> BrowserTypedTextScriptMessageProxy {
        let proxy = BrowserTypedTextScriptMessageProxy(receive: receive)
        userContentController.add(proxy, contentWorld: contentWorld, name: messageHandlerName)
        userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: contentWorld))
        return proxy
    }

    // MARK: - Actions - Messages

    /// Malformed reports keep the page resident rather than authorizing an
    /// unload. Numeric zero is not the script's Boolean startup report.
    static func holdsTypedText(_ body: Any) -> Bool {
        guard let value = body as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return true }
        return value.boolValue
    }
}
