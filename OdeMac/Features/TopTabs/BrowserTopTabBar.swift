import SwiftUI

/// The bar a window lists its tabs in when tabs are on top, in one row: the
/// window's controls, back, forward and reload, the Space, the pinned tabs as
/// icons, the saved and open tabs, New Tab, the address with its site
/// controls, and the sidebar, which comes out over the page for what only it
/// holds. Its empty space moves the window, as a title bar does.
struct BrowserTopTabBar: View {
    // MARK: - Variables

    let model: BrowserRootModel
    let commandSurfaceNamespace: Namespace.ID
    let selectSpace: (UUID) -> Void
    let createSpace: (() -> Void)?

    @Environment(\.browserChromeAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Presentation

    var body: some View {
        if let space = model.browser.shownSpace {
            let items = BrowserTabStripItems(space: space)
            HStack(spacing: OdeSpacing.small) {
                // The window's own controls sit here.
                Color.clear.frame(width: BrowserTopBarMetrics.windowControlsWidth)
                    .accessibilityHidden(true)

                BrowserSidebarNavigationControls(
                    port: BrowserSidebarNavigationPort(
                        pages: model.pages, browser: model.browser,
                        showHistory: { model.chrome.presentUtility(.history) }),
                    capabilities: BrowserInteractionCapabilities()
                )
                .fixedSize()

                BrowserSpaceMenuButton(browser: model.browser, selectSpace: selectSpace, createSpace: createSpace)

                if !items.pinned.isEmpty {
                    HStack(spacing: OdeSpacing.extraExtraSmall) {
                        ForEach(items.pinned, id: \.id) { tab in
                            topTab(tab, in: space, showsTitle: false)
                        }
                    }
                    .fixedSize()
                    Divider().frame(height: appearance.density.topTabHeight * 0.6)
                }

                tabStrip(items, in: space)

                Button("New Tab", systemImage: "plus", action: model.openNewTab)
                    .labelStyle(.iconOnly)
                    .buttonStyle(OdeChromeButtonStyle())
                    .help("New Tab")

                SpaceSidebarAddressBand(
                    space: space,
                    offersSiteControls: !model.browser.isDeleting(space.id),
                    selectedTabID: model.browser.selectedTabID(in: space.id),
                    pages: model.pages,
                    capabilities: BrowserInteractionCapabilities(),
                    address: model.addressBinding,
                    isAddressEditing: model.isAddressEditingBinding,
                    addressFocusRequest: model.chrome.addressFocusRequest,
                    activateAddress: { model.chrome.openLocation(model.address) },
                    submitAddress: model.submitAddress,
                    commandSurfaceNamespace: commandSurfaceNamespace,
                    commandPaletteHandoff: model.commandPaletteHandoff(reduceMotion: reduceMotion),
                    siteControlPresentationChanged: { model.chrome.utilityPresentation.setSiteControlPresented($0) },
                    siteControlContextMenuPresentationChanged: {
                        model.chrome.utilityPresentation.setSiteControlContextMenuPresented($0)
                    }
                )
                .frame(width: BrowserTopBarMetrics.addressWidth)

                Button("Show Sidebar", systemImage: "sidebar.leading") {
                    model.toggleSidebarPanel(reduceMotion: reduceMotion)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(OdeChromeButtonStyle())
                .help("Show Sidebar")
                .padding(.trailing, OdeSpacing.small)
            }
            .frame(height: BrowserChromeLayout.sidebarTitlebarHeight)
            .background { BrowserWindowTitleBarSurface() }
            .spaceColorRoles(for: space.settings.look)
            .environment(\.colorScheme, space.settings.look.foregroundTone.colorScheme)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Tabs"))
        }
    }

    /// The saved and open tabs, sharing the bar's room out between them and
    /// scrolling sideways once each would be narrower than a tab can be.
    private func tabStrip(_ items: BrowserTabStripItems, in space: SpaceModel) -> some View {
        GeometryReader { proxy in
            let entries = items.saved + items.current
            let width = BrowserTopTabMetrics.sharedWidth(
                available: proxy.size.width,
                tabs: entries.count { if case .tab = $0 { true } else { false } },
                folders: entries.count { if case .folder = $0 { true } else { false } },
                spacing: OdeSpacing.extraExtraSmall)
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: OdeSpacing.extraExtraSmall) {
                        ForEach(items.saved) { entry($0, in: space, width: width) }
                        if !items.saved.isEmpty, !items.current.isEmpty {
                            Divider().frame(height: appearance.density.topTabHeight * 0.6)
                        }
                        ForEach(items.current) { entry($0, in: space, width: width) }
                    }
                    .frame(maxHeight: .infinity)
                }
                .scrollIndicators(.never)
                .onChange(of: model.browser.shownTab?.id, initial: true) { _, id in
                    guard let id else { return }
                    withAnimation(OdeMotion.scrollAlignment.unlessReducingMotion(reduceMotion)) {
                        reader.scrollTo("tab-\(id.uuidString)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func entry(_ entry: BrowserTabStripItems.Entry, in space: SpaceModel, width: CGFloat) -> some View {
        switch entry {
        case .tab(let tab):
            topTab(tab, in: space, showsTitle: true, width: width).id(entry.id)
        case .folder(let folder):
            BrowserTopTabFolder(folder: folder, space: space, select: select)
        }
    }

    private func topTab(
        _ tab: TabStateModel, in space: SpaceModel, showsTitle: Bool, width: CGFloat = BrowserTopTabMetrics.idealWidth
    ) -> some View {
        BrowserTopTab(
            tab: tab, space: space, favicons: model.browser.core.state.favicons,
            isSelected: model.browser.shownCards.contains { $0.id == tab.id }, showsTitle: showsTitle, width: width,
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

/// The sizes of the bar of tabs on top.
enum BrowserTopBarMetrics {
    /// The room the window's close, minimize and zoom controls take at the
    /// bar's leading end.
    static let windowControlsWidth: CGFloat = 72
    static let spaceIconSize: CGFloat = 16
    static let addressWidth: CGFloat = 280
}
