import SwiftUI

/// Where a window's sidebar is: beside the page, floating over it, or put away.
struct BrowserSidebarPresentation: Hashable, Sendable {
    // MARK: - Types

    /// Each place shows its own controls, so the view that builds them
    /// switches over the kind.
    enum Kinds: Sendable {
        case docked
        case floating
        case collapsed
    }

    // MARK: - Static Variables

    /// The floating card sits as far inside the window as the page does,
    /// so the two share one corner.
    static let floatingCardInset = OdeCornerScale.gutter

    static let docked = BrowserSidebarPresentation(
        kind: .docked, name: "docked", showsSidebar: true, showsWindowControls: true, reservesSidebarWidth: true,
        sidebarToggleAction: .hide, exitMargin: 0, toggles: { $0.toggleDockedSidebar() })
    static let floating = BrowserSidebarPresentation(
        kind: .floating, name: "floating", showsSidebar: true, showsWindowControls: true, reservesSidebarWidth: false,
        sidebarToggleAction: .dock, exitMargin: 30, toggles: { $0.toggleFloatingSidebar() })
    static let collapsed = BrowserSidebarPresentation(
        kind: .collapsed, name: "collapsed", showsSidebar: false, showsWindowControls: false,
        reservesSidebarWidth: false, sidebarToggleAction: .dock, exitMargin: 0,
        toggles: { $0.toggleCollapsedSidebar() })

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let showsSidebar: Bool
    let showsWindowControls: Bool
    let reservesSidebarWidth: Bool

    /// What the sidebar's toggle does from here.
    let sidebarToggleAction: BrowserSidebarToggleAction

    /// How far past its page-side edge a hovered sidebar here still counts the
    /// pointer as on it, so drifting just off a floating card does not put it
    /// away.
    let exitMargin: CGFloat

    /// Calls the handler's toggle for this place.
    private let toggles: @MainActor @Sendable (any BrowserSidebarToggleHandler) -> Void

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, showsSidebar: Bool, showsWindowControls: Bool, reservesSidebarWidth: Bool,
        sidebarToggleAction: BrowserSidebarToggleAction, exitMargin: CGFloat,
        toggles: @escaping @MainActor @Sendable (any BrowserSidebarToggleHandler) -> Void
    ) {
        self.kind = kind
        self.name = name
        self.showsSidebar = showsSidebar
        self.showsWindowControls = showsWindowControls
        self.reservesSidebarWidth = reservesSidebarWidth
        self.sidebarToggleAction = sidebarToggleAction
        self.exitMargin = exitMargin
        self.toggles = toggles
    }

    /// The place a window's split-view column visibility and floating state
    /// put its sidebar. With tabs on top the sidebar never docks: it floats
    /// over the page while it is out, and is put away otherwise. A docked
    /// sidebar of icons floats in full over the page, over its own column,
    /// while it is out.
    init(
        columnVisibility: NavigationSplitViewVisibility, isFloatingSidebarPresented: Bool,
        tabLayout: BrowserTabLayout = .defaultValue, sidebarStyle: BrowserSidebarStyle = .defaultValue,
        isPageFullscreen: Bool = false
    ) {
        let floatsOverIcons = sidebarStyle.showsIcons && isFloatingSidebarPresented
        // A page alone in full screen has no room beside it, so a docked
        // sidebar can only float over it, and docks again once it ends.
        guard columnVisibility == .detailOnly || tabLayout.showsTopBar || floatsOverIcons || isPageFullscreen
        else {
            self = .docked
            return
        }
        self = isFloatingSidebarPresented ? .floating : .collapsed
    }

    // MARK: - Actions - Layout

    static func floatingHoverRegionWidth(sidebarWidth: CGFloat) -> CGFloat {
        sidebarWidth + (floatingCardInset * 2)
    }

    func reservedWidth(
        for sidebarWidth: CGFloat,
        whileApproachingDock: Bool = false
    ) -> CGFloat {
        reservesSidebarWidth || whileApproachingDock ? sidebarWidth : 0
    }

    // MARK: - Actions - Toggle

    /// Toggles the sidebar from here, as `handler` toggles a sidebar in this place.
    @MainActor
    func toggle(on handler: some BrowserSidebarToggleHandler) {
        toggles(handler)
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSidebarPresentation, rhs: BrowserSidebarPresentation) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
