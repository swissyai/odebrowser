import Foundation

/// The script that puts a page's Boost on it: the same on every engine, in
/// Ode's own script world, which the page cannot see but whose document it
/// shares. It holds the Boost's CSS in one style element at the end of the
/// document, puts it back when the page removes it, and while the person
/// hides elements, outlines the one under the pointer and hides it on a
/// click. It posts to `webkit.messageHandlers.odeBoost` on both engines.
enum BrowserBoostContentBridge {
    // MARK: - Static Variables

    static let handlerName = "odeBoost"
    /// The newest message shape the bridge posts.
    static let messageVersion = 1

    /// Defines `globalThis.__odeBoost` once in a document: `apply(site, css)`
    /// puts `css` on the document when it belongs to `site`, `zap(on, color)`
    /// starts or stops hiding elements, and `start(styles)` applies the CSS
    /// `styles` holds for the document's site and says the document is ready.
    static let runtime = #"""
        (() => {
          "use strict";
          if (globalThis.__odeBoost) return;
          const marker = "data-ode-boost";
          const siteOf = \#(BrowserSite.javaScript);
          const currentSite = () => siteOf(location.hostname);
          const post = (message) => {
            try {
              webkit.messageHandlers.odeBoost.postMessage(Object.assign({ version: 1, site: currentSite() }, message));
            } catch (_) {}
          };
          const root = () => document.documentElement;
          let css = "";
          const pending = new Set();
          let style = null;
          const text = () => {
            let rules = css;
            for (const selector of pending) rules += `\n${selector} { display: none !important; }`;
            return rules;
          };
          const attach = () => {
            const value = text();
            if (!value) { style?.remove(); return; }
            if (!style) {
              style = document.createElement("style");
              style.setAttribute(marker, "");
            }
            if (style.textContent !== value) style.textContent = value;
            const html = root();
            if (html && style.parentNode !== html) html.appendChild(style);
          };
          let watched;
          const observer = new MutationObserver(() => {
            if (style && style.textContent && style.parentNode !== root()) attach();
            watch();
          });
          const watch = () => {
            const html = root();
            if (watched === html) return;
            observer.disconnect();
            observer.observe(document, { childList: true });
            if (html) observer.observe(html, { childList: true });
            watched = html;
          };
          const settle = () => { if (style?.isConnected) root()?.appendChild(style); };
          document.addEventListener("DOMContentLoaded", settle, { once: true });
          addEventListener("load", settle, { once: true });

          const unstable = /\d{3,}|^(css|sc|jsx|svelte|emotion)-|^[a-z]{1,2}\d/i;
          const stable = (token) => token && token.length <= 48 && !unstable.test(token);
          const matchesOne = (selector, element) => {
            try {
              const found = document.querySelectorAll(selector);
              return found.length === 1 && found[0] === element;
            } catch (_) { return false; }
          };
          const step = (element) => {
            if (stable(element.id)) return `#${CSS.escape(element.id)}`;
            let part = CSS.escape(element.localName);
            for (const name of ["data-testid", "data-test-id", "data-qa", "aria-label"]) {
              const value = element.getAttribute(name);
              if (value && value.length <= 64 && !/["\\\n]/.test(value)) { part += `[${name}="${value}"]`; break; }
            }
            part += [...element.classList].filter(stable).slice(0, 3).map(name => `.${CSS.escape(name)}`).join("");
            return part;
          };
          const selectorFor = (element) => {
            const steps = [];
            for (let node = element; node && node.nodeType === 1 && node !== root() && steps.length < 8; node = node.parentElement) {
              let part = step(node);
              steps.unshift(part);
              if (matchesOne(steps.join(" > "), element)) break;
              const parent = node.parentElement;
              const twins = parent ? [...parent.children].filter(child => child.localName === node.localName) : [];
              if (twins.length > 1) {
                steps[0] = `${part}:nth-of-type(${twins.indexOf(node) + 1})`;
                if (matchesOne(steps.join(" > "), element)) break;
              }
            }
            const selector = steps.join(" > ");
            return selector.length <= 512 && matchesOne(selector, element) ? selector : null;
          };

          let zapping = false, target = null, box = null, color = "#3478f6", frame = 0, lastPoint = null;
          const ignored = (element) => !element || element.nodeType !== 1 || element === root() || element === document.body
            || element === box || element === style;
          const place = () => {
            frame = 0;
            if (!box) return;
            if (!zapping || !target || !target.isConnected) { box.style.setProperty("display", "none", "important"); return; }
            const rect = target.getBoundingClientRect();
            const set = (name, value) => box.style.setProperty(name, value, "important");
            set("display", "block");
            set("left", `${rect.left}px`);
            set("top", `${rect.top}px`);
            set("width", `${rect.width}px`);
            set("height", `${rect.height}px`);
          };
          const schedule = () => { if (!frame) frame = requestAnimationFrame(place); };
          const outline = (element) => {
            target = ignored(element) ? null : element;
            if (!box) {
              box = document.createElement("ode-boost-highlight");
              const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
              const set = (name, value) => box.style.setProperty(name, value, "important");
              set("position", "fixed");
              set("pointer-events", "none");
              set("z-index", "2147483647");
              set("box-sizing", "border-box");
              set("border-radius", "6px");
              set("margin", "0");
              set("padding", "0");
              set("transition", still ? "none" : "left 60ms ease-out, top 60ms ease-out, width 60ms ease-out, height 60ms ease-out");
            }
            box.style.setProperty("border", `2px solid ${color}`, "important");
            box.style.setProperty("background", `color-mix(in srgb, ${color} 18%, transparent)`, "important");
            if (box.parentNode !== root()) root()?.appendChild(box);
            schedule();
          };
          const hide = () => {
            const element = target;
            if (!element) return;
            const selector = selectorFor(element);
            if (!selector) return;
            pending.add(selector);
            attach();
            watch();
            target = null;
            schedule();
            post({ kind: "zapped", selector });
          };
          const swallow = (event) => {
            if (!event.isTrusted) return;
            event.preventDefault();
            event.stopImmediatePropagation();
            if (event.type === "pointerdown") outline(event.target);
            if (event.type === "click" && event.button === 0) hide();
          };
          const pointer = (event) => {
            if (!event.isTrusted) return;
            lastPoint = [event.clientX, event.clientY];
            outline(event.target);
          };
          const key = (event) => {
            if (!event.isTrusted || event.key !== "Escape") return;
            event.preventDefault();
            event.stopImmediatePropagation();
            zap(false);
            post({ kind: "zapEnded" });
          };
          const swallowed = ["pointerdown", "pointerup", "mousedown", "mouseup", "click", "auxclick", "dblclick", "contextmenu"];
          let zapStyle = null;
          const listen = (on, type, listener, options) =>
            on ? globalThis.addEventListener(type, listener, options) : globalThis.removeEventListener(type, listener, options);
          const zap = (on, tint) => {
            if (typeof tint === "string" && /^#[0-9a-f]{6}$/i.test(tint)) color = tint;
            if (on === zapping) return true;
            zapping = on;
            for (const type of swallowed) listen(on, type, swallow, { capture: true });
            listen(on, "pointermove", pointer, { capture: true, passive: true });
            listen(on, "scroll", schedule, { capture: true, passive: true });
            listen(on, "keydown", key, { capture: true });
            if (on) {
              zapStyle = zapStyle || document.createElement("style");
              zapStyle.textContent = "html, html * { cursor: crosshair !important; } iframe, embed, object { pointer-events: none !important; }";
              root()?.appendChild(zapStyle);
              if (lastPoint) outline(document.elementFromPoint(lastPoint[0], lastPoint[1]));
            } else {
              zapStyle?.remove();
              target = null;
              schedule();
            }
            return true;
          };
          const apply = (site, next) => {
            if (site !== currentSite()) return false;
            css = typeof next === "string" ? next : "";
            for (const selector of [...pending]) if (css.includes(`${selector} {`)) pending.delete(selector);
            attach();
            watch();
            return true;
          };
          const start = (styles) => {
            const own = styles && typeof styles === "object" ? styles[currentSite()] : null;
            if (typeof own === "string") apply(currentSite(), own);
            watch();
            post({ kind: "ready" });
          };
          Object.defineProperty(globalThis, "__odeBoost", { value: Object.freeze({ apply, zap, start }) });
        })();
        """#

    // MARK: - Actions - Scripts

    /// The script a page's main-frame documents start with: the runtime,
    /// started with `styles`, CSS by site, or with none for an engine whose
    /// documents ask for theirs once they are ready.
    static func documentStart(styles: [String: String]?) -> String {
        let json =
            styles.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) } ?? "null"
        return runtime + "\nglobalThis.__odeBoost.start(\(json));"
    }

    /// Puts `css` on the main document when it belongs to `site`, defining
    /// the runtime first in a document that started without it.
    static let applyBody = runtime + "\nreturn globalThis.__odeBoost.apply(site, css);"

    /// Starts or stops hiding elements in the main document, outlining them
    /// in `color`, a `#rrggbb` color.
    static let zapBody = runtime + "\nreturn globalThis.__odeBoost.zap(on, color);"
}
