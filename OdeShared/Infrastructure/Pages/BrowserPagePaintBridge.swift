import Foundation

/// A page's main document telling Ode it has drawn: its first contentful
/// paint, its load, its return from the back-forward cache, or, once it has
/// drawn, its coming back on screen, each two frames on so the frame is on
/// screen, with the background it painted, or its canvas where it painted
/// none. Both engines run it in a script world the page cannot see, and post
/// through `webkit.messageHandlers.odePagePaint`.
enum BrowserPagePaintBridge {
    // MARK: - Types

    /// What a document said once it drew: the opaque background it painted,
    /// when it painted one.
    struct Report: Equatable {
        let url: URL
        let background: BrowserPageBackground?
    }

    // MARK: - Static Variables

    static let messageHandlerName = "odePagePaint"
    static let script = BrowserContentScript(source: source, handlerName: messageHandlerName, mainFrameOnly: true)

    private static let source = #"""
        (() => {
          let reported = false;
          const transparent = (color) => !color || color === "transparent" || /^rgba\(.*,\s*0\)$/.test(color);
          const post = () => {
            const root = document.documentElement;
            const rootStyle = root ? getComputedStyle(root) : null;
            let color = rootStyle ? rootStyle.backgroundColor : "";
            if (transparent(color) && document.body) color = getComputedStyle(document.body).backgroundColor;
            if (transparent(color)) {
              // The canvas shows through: dark where the page asks for a dark
              // scheme and the person's appearance allows it, else white.
              const schemes = (rootStyle ? rootStyle.colorScheme : "").split(/\s+/);
              const dark = schemes.includes("dark")
                && (!schemes.includes("light") || matchMedia("(prefers-color-scheme: dark)").matches);
              color = dark ? "rgb(18, 18, 18)" : "rgb(255, 255, 255)";
            }
            try {
              globalThis.webkit.messageHandlers.odePagePaint.postMessage({ url: location.href, background: color });
            } catch (_) {}
          };
          const report = () => {
            if (reported) return;
            reported = true;
            post();
          };
          const painted = () => requestAnimationFrame(() => requestAnimationFrame(report));
          try {
            new PerformanceObserver((list) => {
              if (list.getEntriesByName("first-contentful-paint").length) painted();
            }).observe({ type: "paint", buffered: true });
          } catch (_) {}
          addEventListener("load", painted, { once: true });
          addEventListener("pageshow", (event) => {
            if (!event.persisted) return;
            reported = false;
            painted();
          });
          // A document that drew before says so again each time a tab switch
          // brings it back on screen; one that has not drawn yet waits for
          // its first paint.
          addEventListener("visibilitychange", () => {
            if (!reported || document.visibilityState !== "visible") return;
            requestAnimationFrame(() => requestAnimationFrame(post));
          });
        })();
        """#

    // MARK: - Actions - Reports

    /// The report a bridge message carries, or nil for a message that is not
    /// one.
    static func report(_ body: Any) -> Report? {
        guard let fields = body as? [String: Any], let address = fields["url"] as? String,
            let url = URL(string: address)
        else { return nil }
        return Report(url: url, background: (fields["background"] as? String).flatMap(background(css:)))
    }

    /// The opaque colour a computed CSS colour names, as `rgb()` or `rgba()`
    /// with every component written out, the way computed styles report it.
    static func background(css: String) -> BrowserPageBackground? {
        guard let open = css.firstIndex(of: "("), let close = css.lastIndex(of: ")"), open < close else { return nil }
        let function = css[..<open].trimmingCharacters(in: .whitespaces).lowercased()
        guard function == "rgb" || function == "rgba" else { return nil }
        let parts = css[css.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0) }
        guard parts.count == 3 || parts.count == 4, parts.count < 4 || parts[3] == 1,
            parts.prefix(3).allSatisfy({ (0...255).contains($0) })
        else { return nil }
        return BrowserPageBackground(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255)
    }
}
