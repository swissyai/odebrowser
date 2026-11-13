import SwiftUI

struct BrowserRootShell: View, BrowserChromeAnimating {
    // MARK: - Variables

    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let shortcuts: BrowserShortcutStore?
    @Binding var storedSidebarWidth: Double
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var downloadFeedback = BrowserMacDownloadFeedbackState()
    @State private var spacePagerPresentation = SpacePagerPresentation()
    /// The window's tab layout, density and sidebar style.
    @Environment(\.browserChromeAppearance) private var appearance
    @AppStorage(SidebarFullscreenRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarInFullscreen = SidebarFullscreenRevealPreference.defaultValue

    /// The shell places the sidebar; the page frames under it read the rest.
    private var sidebarOnRight: Bool { BrowserDeviceAppearanceStore.shared.sidebarOnRight }
    private var sidebarEdge: HorizontalEdge {
        BrowserChromeAppearance.sidebarEdge(onRight: sidebarOnRight, in: layoutDirection)
    }

    // MARK: - Actions - Presentation

    var body: some View {
        ZStack(alignment: .leading) {
            BrowserRootFullscreenContent(
                pages: model.pages,
                revealsSidebar: revealsSidebarInFullscreen,
                sidebarEdge: sidebarEdge
            ) {
                standardContent
            } sidebar: {
                sidebarSurface
                    .allowsHitTesting(!model.chrome.isCommandPalettePresented)
                    .accessibilityHidden(model.chrome.isCommandPalettePresented)
            } controls: {
                shellControls
                    .allowsHitTesting(!model.chrome.isCommandPalettePresented)
                    .accessibilityHidden(model.chrome.isCommandPalettePresented)
            }

            // Window focus gates the edge reveal in the shell and over a page
            // in full screen alike, so it is followed whichever shows.
            BrowserWindowFocusBridge(isWindowFocused: model.isWindowFocusedBinding)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // The window's chrome belongs to the window, not to the chrome a
            // fullscreen page hides: taking it down would restore the window's
            // style while AppKit is carrying it into fullscreen.
            BrowserNativeWindowControlsBridge(
                isVisible: model.showsWindowControls,
                // The bar of tabs on top keeps the controls at its leading end.
                sidebarOnRight: sidebarOnRight && !appearance.tabLayout.showsTopBar,
                sidebarWidth: model.shownSidebarWidth
            )
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // A held Most Recent Tab shortcut shows the recent tabs over the
            // window, fullscreen page or not.
            BrowserRecentTabsLayer(chrome: model.chrome)

            // Notices show over a fullscreen page too, so one posted there
            // is never lost.
            BrowserNoticeLayer(notices: model.chrome.notices)
        }
        .overlayPreferenceValue(BrowserRootPageBoundsKey.self) { anchor in
            GeometryReader { proxy in
                BrowserFocusPauseLayer(
                    model: model, pageRect: anchor.map { proxy[$0] } ?? CGRect(origin: .zero, size: proxy.size))
            }
        }
        .overlayPreferenceValue(BrowserRootPageBoundsKey.self) { anchor in
            GeometryReader { proxy in
                let rect = anchor.map { proxy[$0] } ?? CGRect(origin: .zero, size: proxy.size)
                BrowserRootCommandPaletteLayer(
                    model: model,
                    shortcuts: shortcuts,
                    spaceSettingsPresentation: spaceSettingsPresentation,
                    commandSurfaceNamespace: commandSurfaceNamespace,
                    contentInsets: BrowserChromeAppearance.contentInsets(
                        for: rect, in: proxy.size, direction: layoutDirection
                    )
                )
            }
        }
        // One per-window host answers for every row and tile in this shell,
        // so the sidebar reads it from here rather than being handed a value
        // per tab through the tree between them.
        .environment(downloadFeedback)
        .environment(model.chrome.tabPreviewHover)
        .environment(\.spacePagerPresentation, spacePagerPresentation)
        .animation(chromeAnimation(OdeMotion.collection), value: sidebarOnRight)
        .onChange(of: appearance.tabLayout, initial: true) { _, layout in
            model.chrome.tabLayout = layout
        }
        .onChange(of: appearance.sidebarStyle, initial: true) { _, style in
            model.chrome.sidebarStyle = style
            model.chrome.iconSidebarHover.dismiss()
        }
        .animation(chromeAnimation(OdeMotion.sidebarMorph), value: appearance.sidebarStyle)
        .animation(
            chromeAnimation(
                model.isSidebarApproachingDock
                    ? OdeMotion.sidebarDockAttachment
                    : OdeMotion.sidebarMorph
            ),
            value: model.chrome.columnVisibility
        )
        .animation(
            chromeAnimation(
                model.isSidebarApproachingDock
                    ? OdeMotion.sidebarDockAttachment
                    : model.isSidebarMorphing
                        ? OdeMotion.sidebarMorph
                        : OdeMotion.floatingPane
            ),
            value: model.isFloatingSidebarPresented
        )
        .animation(
            chromeAnimation(OdeMotion.sidebarDockApproach),
            value: model.isSidebarApproachingDock
        )
        .animation(
            BrowserCommandSurfaceMorph.commandPaletteAnimation(reduceMotion: reduceMotion),
            value: model.isCommandPaletteShown
        )
        .onChange(
            of: model.chrome.utilityPresentation.isSidebarInteractionActive
        ) { _, isActive in
            model.sidebarInteractionChanged(
                isActive,
                reduceMotion: reduceMotion
            )
        }
        .modifier(BrowserRootPermissionObserver(model: model, reduceMotion: reduceMotion))
        .modifier(BrowserRootFullscreenExit(pages: model.pages, chrome: model.chrome))
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: revealsSidebarOverFullscreenPage, initial: true) { _, reveals in
            model.fullscreenSidebarRevealChanged(reveals)
        }
        .onChange(of: transientBrowsing.orphanedPeeks(in: model.browser), initial: true) {
            transientBrowsing.reconcilePeeks(in: model.browser)
        }
        .onChange(of: transientBrowsing.peekRequests, initial: true) {
            model.pages.retainPeekPages(for: transientBrowsing.peekRequests)
        }
    }

    private var standardContent: some View {
        ZStack(alignment: .leading) {
            BrowserRootBackdrop(
                space: model.browser.shownSpace,
                spaces: model.browser.availableSpaces
            )

            VStack(spacing: 0) {
                if model.isTopBarDocked {
                    topTabBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                sidebarPageLayout
            }

            if appearance.tabLayout.showsTopBar, !model.isTopBarDocked {
                BrowserTopBarOverlay(model: model, space: model.browser.shownSpace) { topTabBar }
                    .zIndex(BrowserRootMetrics.floatingSidebarZIndex + 1)
            }

            BrowserMacDownloadFeedbackLayer(model: model, feedback: downloadFeedback)
                .zIndex(BrowserRootMetrics.utilityFanZIndex + 1)

            BrowserRootTabPreviewLayer(model: model, sidebarOnRight: sidebarOnRight)
                .zIndex(BrowserRootMetrics.utilityFanZIndex + 2)

            if model.showsIconSidebar {
                BrowserIconSidebarTitleLayer(
                    hover: model.chrome.iconSidebarHover, sidebarOnRight: sidebarOnRight
                )
                .zIndex(BrowserRootMetrics.utilityFanZIndex + 3)
            }

            BrowserRootDragPreviewLayer(
                model: model,
                reduceMotion: reduceMotion
            )
        }
    }

    /// The bar a window lists its tabs in, with tabs on top.
    private var topTabBar: some View {
        BrowserTopTabBar(
            model: model, commandSurfaceNamespace: commandSurfaceNamespace,
            selectSpace: { spaceID in
                model.browser.selectSpace(spaceID)
                model.pages.selectSpace(in: model.browser)
            },
            createSpace: model.browser.isTemporaryWorkspace ? nil : { _ = try? model.browser.addSpace() })
    }

    /// The page beside the sidebar, which docks beside it, floats over it or
    /// is put away.
    private var sidebarPageLayout: some View {
        BrowserSidebarPageLayout(
            presentation: model.sidebarPresentation,
            width: model.shownSidebarWidth,
            edge: sidebarEdge,
            isApproachingDock: model.isSidebarApproachingDock,
            keptWidth: model.floatsOverIconColumn ? BrowserIconSidebarMetrics.width : nil
        ) {
            VStack(spacing: 0) {
                if model.showsTopAddressBar {
                    BrowserTopAddressBar(model: model, commandSurfaceNamespace: commandSurfaceNamespace)
                }
                BrowserSpacePageSurface(
                    model: model, transientBrowsing: transientBrowsing,
                    tabPromotionNamespace: tabPromotionNamespace, shortcuts: shortcuts
                )
                .clipped()
            }
        } sidebar: {
            sidebarSurface
        } controls: {
            shellControls
        }
        .allowsHitTesting(!model.chrome.isCommandPalettePresented)
        .accessibilityHidden(model.chrome.isCommandPalettePresented)
    }

    private var revealsSidebarOverFullscreenPage: Bool {
        revealsSidebarInFullscreen && model.pages.activePage?.isContentFullscreen == true
    }

    private var sidebarSurface: some View {
        BrowserRootSidebarSurfaceLayer(
            presentation: model.sidebarPresentation,
            width: model.shownSidebarWidth,
            edge: sidebarEdge,
            space: model.browser.shownSpace,
            reduceTransparency: reduceTransparency,
            spaces: model.browser.availableSpaces,
            isRevealedByPointer: model.isFloatingSidebarRevealedByPointer,
            isResizing: model.sidebarWidthTransaction.isResizing,
            hoverChanged: {
                model.sidebarSurfaceHoverChanged(
                    $0,
                    reduceMotion: reduceMotion
                )
            }
        ) {
            BrowserRootSidebarContent(
                model: model,
                spaceSettingsPresentation: spaceSettingsPresentation,
                commandSurfaceNamespace: commandSurfaceNamespace,
                tabPromotionNamespace: tabPromotionNamespace
            )
        }
        .background {
            BrowserSidebarPointerNavigation(
                isSidebarVisible:
                    model.sidebarPresentation.showsSidebar
                    && !model.chrome.isCommandPalettePresented,
                perform: model.handleAuxiliaryMouseAction,
                navigationTargets: { [pages = model.pages] in pages.livePages },
                activeTarget: { [pages = model.pages] in pages.activePage }
            )
        }
    }

    private var shellControls: some View {
        BrowserRootShellControls(
            model: model, storedSidebarWidth: $storedSidebarWidth, sidebarEdge: sidebarEdge)
    }
}

/// Tab selection is observed here so the ordinary shell's inputs stay stable
/// when only the page occupying it changes.
///
/// A page alone in full screen keeps the sidebar's hover area when the person
/// asked for it, and the sidebar floats over the page without moving it.
private struct BrowserRootFullscreenContent<Content: View, Sidebar: View, Controls: View>: View {
    let pages: BrowserPagePool
    let revealsSidebar: Bool
    let sidebarEdge: HorizontalEdge
    @ViewBuilder let content: Content
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let controls: Controls

    var body: some View {
        if let page = pages.activePage, page.isContentFullscreen {
            ZStack(alignment: .leading) {
                BrowserPlatformWebView(
                    page: page,
                    isPageActive: true,
                    focusRestorationGate: .suppressed
                )
                .environment(\.browserPagePresentationWindowID, pages.windowID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)

                if revealsSidebar {
                    sidebar.frame(maxWidth: .infinity, alignment: edgeAlignment)
                    controls.frame(maxWidth: .infinity, alignment: edgeAlignment)
                }
            }
            .ignoresSafeArea()
        } else {
            content
        }
    }

    private var edgeAlignment: Alignment {
        sidebarEdge == .leading ? .leading : .trailing
    }
}

/// Ends a page's fullscreen once the person asks for what it covers: the
/// Command Bar, or another page shown in its place. The page's engine then
/// gives the window back the layout it had.
private struct BrowserRootFullscreenExit: ViewModifier {
    let pages: BrowserPagePool
    let chrome: BrowserChromeState

    func body(content: Content) -> some View {
        content
            .onChange(of: chrome.isCommandPalettePresented) { _, isPresented in
                guard isPresented else { return }
                for page in pages.livePages where page.isContentFullscreen { page.endContentFullscreen() }
            }
            .onChange(of: pages.activePage.map(ObjectIdentifier.init)) {
                let shown = pages.activePage
                for page in pages.livePages where page.isContentFullscreen && page !== shown {
                    page.endContentFullscreen()
                }
            }
    }
}

private struct BrowserRootPermissionObserver: ViewModifier {
    let model: BrowserRootModel
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content.onChange(of: model.pages.activePage?.sitePermissionRequests.current?.id) {
            if model.pages.activePage?.sitePermissionRequests.current != nil {
                model.presentFloatingSidebar(reduceMotion: reduceMotion)
            }
        }
    }
}
