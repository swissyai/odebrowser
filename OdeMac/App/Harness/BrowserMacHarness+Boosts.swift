#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import SwiftUI
    import WebKit

    /// The harness's Boost commands: keep or forget a Boost for the shown
    /// page's site, open the Boost bar, report what the page wears, click the
    /// page as the pointer would, and show the site controls to snapshot.
    extension BrowserMacHarness {
        // MARK: - Actions - Boosts

        /// The page the window shows, which the Boost commands act on.
        private func boostedPage() throws -> BrowserPage {
            guard let page = try context().pages.activePage else { throw Failure(description: "No page is shown") }
            return page
        }

        /// Keeps a Boost for `site`, or the shown page's site, in the shown
        /// page's Space, with the members `arguments` names and the rest
        /// changing nothing.
        func setBoost(_ arguments: [String: Any]) throws -> [String: Any] {
            let page = try boostedPage()
            guard let site = (arguments["site"] as? String) ?? page.boost.site else {
                throw Failure(description: "The shown page has no site")
            }
            var boost = SiteBoost(blankFor: site)
            boost.isEnabled = arguments["isEnabled"] as? Bool ?? true
            boost.isDark = arguments["isDark"] as? Bool ?? false
            boost.tintHue = arguments["tintHue"] as? Double ?? boost.tintHue
            boost.tintStrength = arguments["tintStrength"] as? Double ?? 0
            boost.brightness = arguments["brightness"] as? Double ?? 1
            boost.contrast = arguments["contrast"] as? Double ?? 1
            boost.font = BoostFont.all.first { $0.name == arguments["font"] as? String }
            boost.hiddenSelectors = arguments["hidden"] as? [String] ?? []
            boost.customCss = arguments["css"] as? String ?? ""
            guard try context().browser.setSiteBoost(boost, in: page.spaceID) else {
                throw Failure(description: "The Space did not keep the Boost")
            }
            return ["site": site]
        }

        func removeBoost(site: String?) throws -> [String: Any] {
            let page = try boostedPage()
            guard let site = site ?? page.boost.site else { throw Failure(description: "The shown page has no site") }
            try context().browser.removeSiteBoost(for: site, in: page.spaceID)
            return ["site": site]
        }

        /// Opens or closes the shown page's Boost bar, and starts or stops
        /// hiding elements when `hiding` says.
        func editBoost(on: Bool, hiding: Bool?) throws -> [String: Any] {
            let boost = try boostedPage().boost
            if on {
                boost.beginEditing()
                if let hiding { boost.setHiding(hiding) }
            } else {
                boost.endEditing()
            }
            return ["editing": boost.isEditing, "hiding": boost.isHiding]
        }

        /// What the shown page's Boost session holds and what its main
        /// document wears: the Boost style element's length, the root's
        /// filter, and how many elements its hidden rules hide.
        func boostState() async throws -> [String: Any] {
            let page = try boostedPage()
            let boost = page.boost
            var state: [String: Any] = [
                "available": boost.isAvailable, "site": boost.site ?? "", "editing": boost.isEditing,
                "hiding": boost.isHiding, "documentSite": boost.documentSite ?? "",
                "hidden": boost.shown?.hiddenSelectors ?? [], "enabled": boost.shown?.isEnabled ?? false,
            ]
            if let webView = page.webKitAdapter?.webView {
                let probe = """
                    const style = document.querySelector("style[data-ode-boost]");
                    const css = style ? style.textContent : "";
                    const hidden = css.split("\\n").filter(rule => rule.endsWith("{ display: none !important; }"))
                      .map(rule => rule.slice(0, -" { display: none !important; }".length));
                    let count = 0;
                    for (const selector of hidden) { try { count += document.querySelectorAll(selector).length; } catch (_) {} }
                    return { length: css.length, filter: getComputedStyle(document.documentElement).filter,
                      font: getComputedStyle(document.body || document.documentElement).fontFamily, hiddenElements: count };
                    """
                if let result = try? await webView.callAsyncJavaScript(probe, contentWorld: .page) as? [String: Any] {
                    state["document"] = result
                }
            }
            return state
        }

        /// Moves the pointer to `x`, `y` in the shown page, in points from its
        /// top left, and clicks there, as the window delivers the person's
        /// own clicks, without the real pointer.
        func clickPage(x: Double, y: Double) throws -> [String: Any] {
            guard let page = try context().pages.activePage else { throw Failure(description: "No page is shown") }
            let webView = page.nativeView
            guard let window = webView.window else { throw Failure(description: "The shown page is in no window") }
            let local = NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y)
            let point = webView.convert(local, to: nil)
            for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                guard
                    let event = NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                        clickCount: type == .mouseMoved ? 0 : 1, pressure: type == .leftMouseDown ? 1 : 0)
                else { continue }
                if type == .mouseMoved, page.webKitAdapter != nil {
                    webView.mouseMoved(with: event)
                } else {
                    window.sendEvent(event)
                }
            }
            return ["x": point.x, "y": point.y]
        }

        /// Shows the open Boost bar's colors or CSS, as its buttons do, in a
        /// window titled "Boost Colors" or "Boost CSS" that `snapshotWindow`
        /// can draw.
        func showBoostPanel(_ panel: String) throws -> [String: Any] {
            let boost = try boostedPage().boost
            guard boost.isEditing else { throw Failure(description: "The Boost bar is not open") }
            if panel == "css" {
                return show(BrowserBoostStylesheetEditor(boost: boost), titled: "Boost CSS", width: 480)
            }
            return show(BrowserBoostColorsPanel(boost: boost), titled: "Boost Colors", width: 340)
        }

        /// Shows the shown page's site controls, as its address's site button
        /// does, in a window titled "Site Controls" that `snapshotWindow` can
        /// draw.
        func showSiteControls() throws -> [String: Any] {
            let context = try context()
            let page = try boostedPage()
            guard let space = context.browser.spaceModel(page.spaceID) else {
                throw Failure(description: "The shown page has no Space")
            }
            let configuration = BrowserSiteControlConfiguration(
                page: page, space: space, selectedTabID: context.browser.shownTab?.id,
                permissionCenter: page.permissionCenter, tabPreviews: context.pages.runtimeStore.tabPreviews,
                presentationChanged: { _ in },
                contextMenuPresentationChanged: { _ in })
            return show(
                BrowserSiteControlContent(
                    configuration: configuration, permissionsExpansion: .constant(false), dismiss: {},
                    reviewCertificate: {}),
                titled: "Site Controls", width: 300)
        }
    }

#endif
