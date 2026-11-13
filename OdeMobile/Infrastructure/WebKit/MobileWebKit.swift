import UIKit
import WebKit

/// What only iPhone and iPad WebKit pages need, which WebKit's binding applies
/// as it builds a page: the presentation WebKit recommends, inline media that
/// waits for the person, and the web view.
@MainActor
enum MobileWebKit {
    // MARK: - Static Variables

    static let preferredContentMode = WKWebpagePreferences.ContentMode.recommended

    /// The widest page that asks for a site's mobile version.
    static let mobileContentMaximumWidth: CGFloat = 700

    /// Keeps every video, including ones a page adds later, playing inline
    /// rather than taking over the screen.
    static let inlineVideoScript = WKUserScript(
        source: """
            (() => {
              const keepInline = (root) => {
                if (root instanceof HTMLVideoElement) {
                  root.setAttribute('playsinline', '');
                  root.setAttribute('webkit-playsinline', '');
                }
                root.querySelectorAll?.('video').forEach((video) => {
                  video.setAttribute('playsinline', '');
                  video.setAttribute('webkit-playsinline', '');
                });
              };

              keepInline(document);
              new MutationObserver((records) => {
                records.forEach((record) => {
                  record.addedNodes.forEach((node) => {
                    if (node instanceof Element) keepInline(node);
                  });
                });
              }).observe(document.documentElement, { childList: true, subtree: true });
            })();
            """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    // MARK: - Actions - Content mode

    /// The version of a site a page `width` points wide asks for: the desktop
    /// site when the person asked for it; the mobile site while the page is
    /// narrower than a tablet's page column, as on a phone, in a narrow iPad
    /// window or in a Quick Window card; and otherwise what WebKit recommends.
    /// A first navigation can precede host layout, so an unknown width also
    /// uses the readable mobile version without reloading after layout.
    static func contentMode(
        forWidth width: CGFloat,
        requestsDesktopSite: Bool
    ) -> WKWebpagePreferences.ContentMode {
        if requestsDesktopSite { return .desktop }
        guard width < mobileContentMaximumWidth else { return preferredContentMode }
        return .mobile
    }

    // MARK: - Actions - Pages

    /// Adds the mobile media policy to a new page's configuration, on top of
    /// the settings both platforms share: the inactive scheduling policy above
    /// all, which lets WebKit suspend a resident background tab on the
    /// platform that jetsams.
    static func decorate(_ configuration: WKWebViewConfiguration) {
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.addUserScript(inlineVideoScript)
    }

    /// The web view over `configuration`, one the binding assembled or one
    /// WebKit made for a popup.
    static func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear
        return webView
    }

    // MARK: - Actions - Snapshots

    /// The pixels of `image`, a snapshot WebKit took of a page, and how many
    /// of them make a point.
    static func bitmap(of image: UIImage) -> (image: CGImage, scale: CGFloat)? {
        guard let bitmap = image.cgImage else { return nil }
        return (bitmap, CGFloat(bitmap.width) / max(image.size.width, 1))
    }
}
