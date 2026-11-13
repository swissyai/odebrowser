import SwiftUI

/// The docked sidebar as a narrow column of icons, for small screens: the
/// window's controls, back and forward, the address, the pinned tabs, the
/// saved and open tabs and folders, New Tab, the Space and its switcher, and
/// the way back to the full sidebar. Titles show beside an icon while the
/// pointer rests on it.
struct BrowserIconSidebar: View {
    // MARK: - Variables

    let model: BrowserRootModel
    let selectSpace: (UUID) -> Void
    let createSpace: (() -> Void)?

    @Environment(\.browserChromeAppearance) private var appearance

    private var showsNavigation: Bool {
        !model.showsTopAddressBar || model.pages.activePage?.isContentFullscreen == true
    }

    // MARK: - Actions - Presentation

    var body: some View {
        if let space = model.browser.shownSpace {
            let items = BrowserTabStripItems(space: space)
            let port = BrowserSidebarNavigationPort(
                pages: model.pages, browser: model.browser, showHistory: { model.chrome.presentUtility(.history) })
            VStack(spacing: OdeSpacing.small) {
                // The window's own controls sit in this band, which moves the
                // window as a title bar does.
                Color.clear
                    .frame(height: BrowserChromeLayout.sidebarTitlebarHeight)
                    .background { BrowserWindowTitleBarSurface() }
                    .accessibilityHidden(true)

                if showsNavigation {
                    HStack(spacing: OdeSpacing.extraExtraSmall) {
                        Button("Back", systemImage: "chevron.left", action: port.goBack)
                            .disabled(!port.canGoBack())
                        Button("Forward", systemImage: "chevron.right", action: port.goForward)
                            .disabled(!port.canGoForward())
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(OdeChromeButtonStyle())

                    Button("Search or Enter Address", systemImage: "magnifyingglass") {
                        model.chrome.openLocation(model.address)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(OdeChromeButtonStyle())
                    .help("Search or Enter Address")
                }

                ScrollView(.vertical) {
                    VStack(spacing: OdeSpacing.extraExtraSmall) {
                        ForEach(items.pinned, id: \.id) { icon($0, in: space) }
                        if !items.pinned.isEmpty, !items.saved.isEmpty || !items.current.isEmpty { separator }
                        ForEach(items.saved) { entry($0, in: space) }
                        if !items.saved.isEmpty, !items.current.isEmpty { separator }
                        ForEach(items.current) { entry($0, in: space) }
                    }
                    .padding(.vertical, OdeSpacing.extraSmall)
                    .frame(maxWidth: .infinity)
                    .background { BrowserSidebarCommandScrollBridge.DocumentMarker() }
                }
                .scrollIndicators(.never)

                Button("New Tab", systemImage: "plus", action: model.openNewTab)
                    .labelStyle(.iconOnly)
                    .buttonStyle(OdeChromeButtonStyle())
                    .help("New Tab")

                BrowserSpaceMenuButton(browser: model.browser, selectSpace: selectSpace, createSpace: createSpace)

                Button("Show Full Sidebar", systemImage: "sidebar.leading") { model.setSidebarStyle(.full) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(OdeChromeButtonStyle())
                    .help("Show Full Sidebar")
                    .padding(.bottom, OdeSpacing.small)
            }
            .frame(width: BrowserIconSidebarMetrics.width)
            .frame(maxHeight: .infinity)
            .spaceColorRoles(for: space.settings.look)
            .environment(\.colorScheme, space.settings.look.foregroundTone.colorScheme)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("\(space.settings.name) Space"))
        }
    }

    private var separator: some View {
        Divider().frame(width: BrowserIconSidebarMetrics.iconWidth * 0.6)
    }

    @ViewBuilder
    private func entry(_ entry: BrowserTabStripItems.Entry, in space: SpaceModel) -> some View {
        switch entry {
        case .tab(let tab):
            icon(tab, in: space)
        case .folder(let folder):
            BrowserTopTabFolder(folder: folder, space: space, showsTitle: false, select: select)
        }
    }

    private func icon(_ tab: TabStateModel, in space: SpaceModel) -> some View {
        BrowserIconSidebarTab(
            tab: tab, space: space, favicons: model.browser.core.state.favicons,
            isSelected: model.browser.shownCards.contains { $0.id == tab.id }, hover: model.chrome.iconSidebarHover,
            select: { select(tab.id) },
            close: { model.browser.closeTab(tab.id, matching: BrowserSpaceRuntimeAssignment(space: space)) },
            togglePin: { _ = try? model.browser.togglePin(tab.id) },
            duplicate: {
                guard model.browser.duplicateTab(tab.id, in: space.id) != nil else { return }
                model.pages.select()
            })
    }

    private func select(_ tabID: UUID) {
        model.browser.selectTab(tabID)
        model.pages.select()
    }
}

/// The sizes of the sidebar as icons.
enum BrowserIconSidebarMetrics {
    /// Wide enough for the window's close, minimize and zoom controls, which
    /// sit at its top.
    static let width: CGFloat = 84
    static let iconWidth: CGFloat = 52

    /// How tall one icon's row is at `density`.
    static func rowHeight(_ density: BrowserLayoutDensity) -> CGFloat {
        max(OdeLayout.minimumHitTarget, 36 * density.rowScale)
    }
}
