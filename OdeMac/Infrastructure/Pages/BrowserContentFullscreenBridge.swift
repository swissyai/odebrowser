import Foundation

/// A page's main document telling Ode it entered or left fullscreen, on an
/// engine that runs Ode's content bridges. The engine reports the same through
/// `BrowserPageContentFullscreenChanged`; the document's own word keeps the
/// page shown alone exactly while it is fullscreen, whatever the engine's
/// report missed, and lets Ode end a page's fullscreen and ask whether it
/// still holds.
@MainActor
enum BrowserContentFullscreenBridge {
    // MARK: - Static Variables

    static let messageHandlerName = "odeContentFullscreen"
    static let script = BrowserContentScript(source: source, handlerName: messageHandlerName, mainFrameOnly: true)
    /// Answers whether the main document is fullscreen now.
    static let isFullscreen = "return document.fullscreenElement != null;"
    /// Ends the main document's fullscreen, as the page's own exit does.
    static let exit =
        "if (document.fullscreenElement) { await document.exitFullscreen().catch(() => {}); } return true;"

    private static let source = #"""
        (() => {
          let reported = null;
          const report = () => {
            const active = document.fullscreenElement != null;
            if (active === reported) return;
            reported = active;
            try {
              globalThis.webkit.messageHandlers.odeContentFullscreen.postMessage(active);
            } catch (_) {}
          };
          document.addEventListener("fullscreenchange", report, true);
          document.addEventListener("webkitfullscreenchange", report, true);
        })();
        """#
}
