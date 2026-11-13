#if DEBUG || ODE_REVIEW_BUILD

    import AppKit
    import Foundation

    /// The harness's layout commands: toggle the sidebar as Command-S does,
    /// bring a hidden sidebar out as a pointer resting on the window's edge
    /// would, and report where the sidebar is and what the Command Bar has
    /// selected.
    extension BrowserMacHarness {
        // MARK: - Actions - Sidebar

        /// Runs Toggle Sidebar in the last-used window, as its key does, and
        /// reports the sidebar once `settle` seconds have passed.
        func toggleSidebar(settle: Double) async throws -> [String: Any] {
            try commands().perform(.toggleSidebar)
            try? await Task.sleep(for: .seconds(settle))
            return try sidebarState()
        }

        /// Brings a hidden sidebar out over the page, or puts it away, as the
        /// pointer reaching or leaving the window's edge does.
        /// With tabs on top, brings the sidebar out over the page as its
        /// button does.
        func peekSidebar(_ on: Bool, settle: Double) async throws -> [String: Any] {
            let chrome = try context().chrome
            guard chrome.columnVisibility == .detailOnly || chrome.tabLayout.showsTopBar else {
                throw Failure(description: "The sidebar is docked")
            }
            chrome.isFloatingSidebarPresented = on
            try? await Task.sleep(for: .seconds(settle))
            return try sidebarState()
        }

        // MARK: - Actions - Layout

        /// Brings a hidden bar of tabs on top out over the page, or puts it
        /// away, as the pointer reaching or leaving the window's top edge does.
        func peekTopBar(_ on: Bool, settle: Double) async throws -> [String: Any] {
            let chrome = try context().chrome
            guard chrome.tabLayout.showsTopBar, chrome.columnVisibility == .detailOnly else {
                throw Failure(description: "No bar of tabs on top is hidden")
            }
            chrome.isTopBarRevealed = on
            try? await Task.sleep(for: .seconds(settle))
            return try sidebarState()
        }

        /// Sets where windows list their tabs, `sidebar` or `top`, how the
        /// sidebar shows, `full` or `icons`, and the layout density,
        /// `comfortable` or `compact`, as Appearance settings do, and reports
        /// the sidebar once `settle` seconds have passed.
        func setLayout(tabs: String?, density: String?, sidebar: String?, settle: Double) async throws -> [String: Any]
        {
            let defaults = BrowserChromeAppearancePreference.defaults
            if let sidebar {
                defaults.set(
                    BrowserSidebarStyle.named(sidebar).name, forKey: BrowserChromeAppearancePreference.sidebarStyleKey)
            }
            if let tabs {
                defaults.set(BrowserTabLayout.named(tabs).name, forKey: BrowserChromeAppearancePreference.tabLayoutKey)
            }
            if let density {
                defaults.set(
                    BrowserLayoutDensity.named(density).name, forKey: BrowserChromeAppearancePreference.densityKey)
            }
            try? await Task.sleep(for: .seconds(settle))
            return try sidebarState()
        }

        /// Shows the title of the shown Space's tab whose address or title
        /// holds `text` beside its icon, as the pointer resting on it does in
        /// the sidebar as icons.
        func showIconTitle(matching text: String) throws -> [String: Any] {
            let context = try context()
            guard
                let tab = context.browser.shownSpace?.tabs.models.first(where: {
                    ($0.url ?? "").contains(text) || $0.title.contains(text)
                })
            else { throw Failure(description: "No tab in the shown Space matches \(text)") }
            guard context.chrome.iconSidebarHover.show(tab.title, of: tab.id) else {
                throw Failure(description: "The tab has no icon on screen")
            }
            return ["title": tab.title]
        }

        /// Scrolls the shown Space's tab list to `y` points from its top, as
        /// a scroll wheel would, and reports where it came to rest.
        func scrollSidebar(to y: Double) throws -> [String: Any] {
            let list = try tabList()
            let limit = (list.documentView?.frame.height ?? 0) - list.contentSize.height
            list.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), limit)))
            list.reflectScrolledClipView(list.contentView)
            return ["y": list.contentView.bounds.minY, "limit": limit]
        }

        /// Where the shown Space's tab list rests, and how far it can scroll.
        func sidebarOffset() throws -> [String: Any] {
            let list = try tabList()
            let limit = (list.documentView?.frame.height ?? 0) - list.contentSize.height
            return ["y": list.contentView.bounds.minY, "limit": limit, "visible": list.contentSize.height]
        }

        /// The shown Space's tab list, the sidebar's scroll view that scrolls.
        private func tabList() throws -> NSScrollView {
            let window = try targetWindow()
            guard let content = window.contentView,
                let list = Self.scrollViews(in: content).first(where: { scrollView in
                    let frame = scrollView.convert(scrollView.bounds, to: nil)
                    return !scrollView.isHiddenOrHasHiddenAncestor && frame.minX >= 0 && frame.minX < 100
                        && frame.intersects(content.bounds)
                        && (scrollView.documentView?.frame.height ?? 0) > scrollView.contentSize.height
                })
            else { throw Failure(description: "No tab list scrolls") }
            return list
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews(in:))
        }

        /// Where the last-used window's sidebar is: docked, floating or
        /// collapsed.
        func sidebarState() throws -> [String: Any] {
            let chrome = try context().chrome
            let presentation = Self.presentation(of: chrome)
            let topBar = chrome.columnVisibility == .detailOnly ? "hidden" : "shown"
            return [
                "sidebar": presentation.name, "tabs": chrome.tabLayout.name, "style": chrome.sidebarStyle.name,
                "topBar": chrome.tabLayout.showsTopBar ? topBar : "none",
            ]
        }

        // MARK: - Actions - Nested tabs

        /// Turns nesting tabs opened from pages on or off, as Settings does.
        func setNesting(_ nests: Bool) -> [String: Any] {
            BrowserAppPreferenceStore.shared.nestsTabsOpenedFromPages = nests
            return ["nests": BrowserAppPreferenceStore.shared.nestsTabsOpenedFromPages]
        }

        /// Opens `address` in a new tab of the shown Space as a link the page of
        /// the tab matching `text` followed opens it, shown when `shows`.
        func openFromTab(_ address: String, matching text: String, shows: Bool) throws -> [String: Any] {
            let browser = try context().browser
            guard let url = URL(string: address), let space = browser.shownSpace,
                let opener = Self.tab(matching: text, in: space)
            else { throw Failure(description: "openFromTab needs a url and a tab matching \(text)") }
            guard let tabID = browser.openNewTab(url: url, in: space.id, selecting: shows, openedFrom: opener.id) else {
                throw Failure(description: "The Space refused the tab")
            }
            return ["tabID": tabID.uuidString]
        }

        /// Hides or shows the tabs nested under the tab matching `text`.
        func collapseNested(matching text: String, collapsed: Bool) throws -> [String: Any] {
            let browser = try context().browser
            guard let space = browser.shownSpace, let tab = Self.tab(matching: text, in: space) else {
                throw Failure(description: "No tab in the shown Space matches \(text)")
            }
            let done = browser.collapseNestedTabs(
                collapsed, under: tab.id, matching: BrowserSpaceRuntimeAssignment(space: space))
            return ["collapsed": done ? collapsed : !collapsed]
        }

        /// The shown Space's open tabs in order, each with how deep it nests,
        /// how many tabs nest under it, and whether it or a tab above hides them.
        func tabTree() throws -> [String: Any] {
            let browser = try context().browser
            guard let space = browser.shownSpace else { throw Failure(description: "No Space is shown") }
            let rows = space.sidebar.section(.current).rows.map { row -> [String: Any] in
                [
                    "title": space.tabs.model(row.id)?.title ?? "", "depth": row.treeDepth, "nested": row.nestedTabs,
                    "collapses": row.collapsesNestedTabs, "hidden": row.isHiddenInTree,
                ]
            }
            return ["rows": rows]
        }

        /// The tab of `space` whose title or address holds `text`.
        private static func tab(matching text: String, in space: SpaceModel) -> TabStateModel? {
            space.tabs.models.first { $0.title.contains(text) || ($0.url ?? "").contains(text) }
        }
    }

#endif
