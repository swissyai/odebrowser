import SwiftUI

/// The side-tab layout's address strip belongs to the page area, not the
/// sidebar's dock or floating card. The existing band still owns activation,
/// security, site controls and copying for the selected Space and page.
struct BrowserTopAddressBar: View {
    // MARK: - Variables

    let model: BrowserRootModel
    let commandSurfaceNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var navigationWidth: CGFloat {
        let metrics = BrowserSidebarNavigationControlMetrics.pointer
        return metrics.leadingSpacerMinimum + metrics.controlSize.width * 3
            + metrics.reloadMenuControlSize.width + metrics.controlSpacing * 2
            + metrics.leadingInset + metrics.trailingInset
    }

    /// Only enable page controls for this selection. Navigation still runs
    /// through the pool's canonical routes, including reload's page selection
    /// and focus recovery, rather than calling a retained page directly.
    private var displayedPage: BrowserPage? {
        guard !model.selectedSpaceIsLocked,
            model.browser.workspaceModel?.kind.isPractice != true,
            model.browser.shownTab?.surface.showsPage == true,
            let assignment = model.selectedTabAssignment
        else { return nil }
        return model.pages.activePage(matching: assignment)
    }

    private var navigationPort: BrowserSidebarNavigationPort {
        BrowserSidebarNavigationPort(
            pages: model.pages, browser: model.browser, showHistory: { model.chrome.presentUtility(.history) })
    }

    // MARK: - Actions - Presentation

    var body: some View {
        if let space = model.browser.shownSpace {
            GeometryReader { proxy in
                bar(in: space, width: proxy.size.width)
            }
            .frame(height: BrowserChromeLayout.sidebarTitlebarHeight)
            .background { BrowserWindowTitleBarSurface() }
            .spaceColorRoles(for: space.settings.look)
            .modifier(SpaceColorScheme(branding: space.settings.look))
            .modifier(SpaceForegroundBlend(spaces: model.browser.availableSpaces, selectedSpaceID: space.id))
            .accessibilityElement(children: .contain)
        }
    }

    private func bar(in space: SpaceModel, width: CGFloat) -> some View {
        // At the window's minimum width a docked sidebar can leave less room
        // than the navigation strip alone needs. Keep one address band and
        // move navigation into a native menu rather than adding another row.
        let showsNavigation =
            width >= navigationWidth * 2 + BrowserChromeLayout.sidebarMinimumWidth + OdeSpacing.small * 4
        let isLocked = model.spaceAccess.isLocked(space)
        return HStack(spacing: OdeSpacing.small) {
            if showsNavigation {
                BrowserSidebarNavigationControls(
                    port: navigationPort, capabilities: BrowserInteractionCapabilities()
                )
                .frame(width: navigationWidth)
                .disabled(displayedPage == nil)
            }

            addressBand(in: space, isLocked: isLocked)
                .frame(maxWidth: BrowserCommandPaletteMetrics.maximumCardWidth)
                .frame(maxWidth: .infinity)

            if showsNavigation {
                Button("Toggle Sidebar", systemImage: "sidebar.leading", action: toggleSidebar)
                    .labelStyle(.iconOnly)
                    .buttonStyle(OdeChromeButtonStyle())
                    .help("Toggle Sidebar")
                    .frame(width: navigationWidth, alignment: .trailing)
            } else {
                navigationMenu
            }
        }
        .padding(.horizontal, OdeSpacing.small)
        .frame(maxHeight: .infinity)
    }

    private var navigationMenu: some View {
        let port = navigationPort
        return Menu {
            Group {
                Button("Back", systemImage: "chevron.left", action: port.goBack)
                    .disabled(displayedPage == nil || !port.canGoBack())
                Button("Forward", systemImage: "chevron.right", action: port.goForward)
                    .disabled(displayedPage == nil || !port.canGoForward())
                if displayedPage?.live.isLoading == true {
                    Button("Stop Loading", systemImage: "xmark", action: port.reloadOrStop)
                        .disabled(displayedPage == nil)
                } else {
                    Button("Reload", systemImage: "arrow.clockwise", action: port.reload)
                        .disabled(displayedPage == nil)
                }
                Divider()
                Button("Toggle Sidebar", systemImage: "sidebar.leading", action: toggleSidebar)
            }
            .odeMenuActionLabelStyle()
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(OdeChromeButtonStyle())
        .fixedSize()
        .accessibilityLabel("Navigation")
    }

    // MARK: - Actions - Sidebar

    private func toggleSidebar() {
        model.toggleSidebar(reduceMotion: reduceMotion)
    }

    // MARK: - Actions - Address

    @ViewBuilder
    private func addressBand(in space: SpaceModel, isLocked: Bool) -> some View {
        if !isLocked {
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
                },
                showsSummaryRoute: false
            )
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }
}
