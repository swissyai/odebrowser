import SwiftUI

/// The window's address and navigation stay in place while Space contents move
/// underneath. Their native field and popover identities belong to this leaf.
struct SidebarChrome: View {
    // MARK: - Variables

    let context: BrowserSidebarContext
    let pages: BrowserPagePool
    let address: Binding<String>
    let isAddressEditing: Binding<Bool>
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let commandPaletteHandoff: BrowserCommandPaletteHandoff

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fullscreen pages hide the independent top strip. Their optional
    /// sidebar reveal retains the original navigation and address controls.
    private var keepsOnlyTitleBar: Bool {
        BrowserDeviceAppearanceStore.shared.address.placement.showsTopBar
            && pages.activePage?.isContentFullscreen != true
    }

    // MARK: - Actions - Presentation

    var body: some View {
        if let space = selectedSpace {
            let isLocked = context.spaceAccess.isLocked(space)

            VStack(spacing: 0) {
                if keepsOnlyTitleBar {
                    Color.clear
                        .frame(height: BrowserChromeLayout.sidebarTitlebarHeight)
                        .background { BrowserWindowTitleBarSurface() }
                        .accessibilityHidden(true)
                } else {
                    BrowserSidebarNavigationControls(
                        port: BrowserSidebarNavigationPort(
                            pages: pages, browser: context.browser, showHistory: context.chromeActions.presentHistory),
                        capabilities: context.capabilities
                    )
                    .contentTransition(.opacity)
                    .background {
                        // Only the empty navigation-strip background acts as the
                        // title bar. Controls and tab gestures keep their input.
                        BrowserWindowTitleBarSurface()
                    }
                    // Another tab's history shows at once, as every browser switches
                    // tabs; a fade on each switch redraws the strip every frame.
                    .animation(nil, value: pages.activeTabID)
                    .animation(
                        SpacePagerSettlement.standardAnimation.unlessReducingMotion(reduceMotion),
                        value: [pages.canGoBack, pages.canGoForward, pages.activePage?.live.isLoading == true]
                    )

                    if context.utilityPresentation.surface == nil {
                        SpaceSidebarAddressBand(
                            space: space,
                            offersSiteControls: !context.browser.isDeleting(space.id),
                            selectedTabID: context.browser.selectedTabID(in: space.id),
                            pages: pages,
                            capabilities: context.capabilities,
                            address: address,
                            isAddressEditing: isAddressEditing,
                            addressFocusRequest: addressFocusRequest,
                            activateAddress: activateAddress,
                            submitAddress: submitAddress,
                            commandSurfaceNamespace: commandSurfaceNamespace,
                            commandPaletteHandoff: commandPaletteHandoff,
                            siteControlPresentationChanged: {
                                context.utilityPresentation.setSiteControlPresented($0)
                            },
                            siteControlContextMenuPresentationChanged: {
                                context.utilityPresentation.setSiteControlContextMenuPresented($0)
                            }
                        )
                    }
                }
            }
            .spaceColorRoles(for: space.settings.look)
            .modifier(SpaceColorScheme(branding: space.settings.look))
            .modifier(SpaceForegroundBlend(spaces: context.availableSpaces, selectedSpaceID: space.id))
            .blur(radius: isLocked ? BrowserSidebarMetrics.lockedSpaceBlurRadius : 0)
            .redacted(reason: isLocked ? .placeholder : [])
            .allowsHitTesting(!isLocked)
            .accessibilityHidden(isLocked)
        }
    }

    /// The Space the window shows, unless it is being deleted.
    private var selectedSpace: SpaceModel? {
        context.browser.shownSpace
    }
}
