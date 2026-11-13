import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserChromeState {
    // MARK: - Variables

    let utilityPresentation: BrowserUtilityPresentationState
    /// Which pinned or saved tab's preview card the window shows.
    let tabPreviewHover = BrowserTabPreviewHover()
    /// The title the sidebar as icons shows beside the icon under the pointer.
    let iconSidebarHover = BrowserIconSidebarHover()
    /// The notice this window shows at its top.
    let notices = BrowserNotices()
    var columnVisibility: NavigationSplitViewVisibility {
        get { observed(\.columnVisibilityStorage, as: \.columnVisibility) }
        set { publish(newValue, into: \.columnVisibilityStorage, as: \.columnVisibility) }
    }
    @ObservationIgnored private var columnVisibilityStorage: NavigationSplitViewVisibility
    /// Whether the undocked sidebar is floating over the page, as it does while
    /// the pointer rests at the window's edge.
    var isFloatingSidebarPresented: Bool {
        get { observed(\.isFloatingSidebarPresentedStorage, as: \.isFloatingSidebarPresented) }
        set { publish(newValue, into: \.isFloatingSidebarPresentedStorage, as: \.isFloatingSidebarPresented) }
    }
    @ObservationIgnored private var isFloatingSidebarPresentedStorage = false
    /// Where the window lists its tabs. With tabs on top the column flag
    /// stands for the bar of tabs, and the sidebar only ever floats.
    var tabLayout: BrowserTabLayout {
        get { observed(\.tabLayoutStorage, as: \.tabLayout) }
        set { publish(newValue, into: \.tabLayoutStorage, as: \.tabLayout) }
    }
    @ObservationIgnored private var tabLayoutStorage = BrowserTabLayout.defaultValue
    /// How the docked sidebar shows: in full, or as icons.
    var sidebarStyle: BrowserSidebarStyle {
        get { observed(\.sidebarStyleStorage, as: \.sidebarStyle) }
        set { publish(newValue, into: \.sidebarStyleStorage, as: \.sidebarStyle) }
    }
    @ObservationIgnored private var sidebarStyleStorage = BrowserSidebarStyle.defaultValue
    /// Whether a hidden bar of tabs on top is out over the page, as it is
    /// while the pointer rests at the window's top edge.
    var isTopBarRevealed: Bool {
        get { observed(\.isTopBarRevealedStorage, as: \.isTopBarRevealed) }
        set { publish(newValue, into: \.isTopBarRevealedStorage, as: \.isTopBarRevealed) }
    }
    @ObservationIgnored private var isTopBarRevealedStorage = false
    /// Whether a page shows alone in full screen with the sidebar hover area
    /// still live, where a docked sidebar gives way to the edge reveal.
    var revealsSidebarOverFullscreenPage: Bool {
        get { observed(\.revealsSidebarOverFullscreenPageStorage, as: \.revealsSidebarOverFullscreenPage) }
        set {
            publish(newValue, into: \.revealsSidebarOverFullscreenPageStorage, as: \.revealsSidebarOverFullscreenPage)
        }
    }
    @ObservationIgnored private var revealsSidebarOverFullscreenPageStorage = false
    private(set) var commandPaletteMode: BrowserCommandPaletteMode? {
        get { observed(\.commandPaletteModeStorage, as: \.commandPaletteMode) }
        set { publish(newValue, into: \.commandPaletteModeStorage, as: \.commandPaletteMode) }
    }
    @ObservationIgnored private var commandPaletteModeStorage: BrowserCommandPaletteMode?
    private(set) var addressFocusRequest = 0
    private(set) var startPageFocusRequest = 0
    /// The recent tabs a held Most Recent Tab shortcut shows over the window,
    /// or nil while none shows.
    var recentTabs: RecentTabSwitcherModel? {
        get { observed(\.recentTabsStorage, as: \.recentTabs) }
        set {
            guard recentTabsStorage !== newValue else { return }
            recentTabsStorage = newValue
            withMutation(keyPath: \.recentTabs) {}
        }
    }
    @ObservationIgnored private var recentTabsStorage: RecentTabSwitcherModel?
    /// Toggles the sidebar as the window's own sidebar button does, with its
    /// motion and its handling of a pointer resting on the sidebar. The
    /// window showing this chrome sets it; without one, Toggle Sidebar flips
    /// the sidebar's column at once.
    @ObservationIgnored var sidebarToggle: (@MainActor () -> Void)?

    var isCommandPalettePresented: Bool {
        commandPaletteMode != nil
    }

    /// Whether the palette is open to edit the shown tab's address.
    var isEditingLocation: Bool {
        guard case .editLocation = commandPaletteMode else { return false }
        return true
    }

    // MARK: - Initializers

    init(
        sidebarIsPresented: Bool = true,
        utilityPresentation: BrowserUtilityPresentationState =
            BrowserUtilityPresentationState()
    ) {
        columnVisibilityStorage = sidebarIsPresented ? .all : .detailOnly
        self.utilityPresentation = utilityPresentation
    }

    // MARK: - Actions - Sidebar

    /// Whether History, the Archive and Downloads come out in the full
    /// sidebar over the page: with tabs on top, which dock no sidebar, and
    /// with a docked column of icons, which has no room for a list.
    private var floatsUtilities: Bool {
        tabLayout.showsTopBar || sidebarStyle.showsIcons && columnVisibility != .detailOnly
    }

    /// Hiding cancels utility presentation and pending input before an asynchronous view update can mount it.
    func hideSidebar() {
        utilityPresentation.dismiss()
        columnVisibility = .detailOnly
    }

    func showSidebar() {
        columnVisibility = .all
    }

    /// Brings `surface` up in the sidebar. Every route to History, Archive and
    /// Downloads comes through here, so none can open its list in a sidebar no
    /// one can see: a hidden sidebar docks first, and one floating over the
    /// page keeps floating.
    func presentUtility(_ surface: BrowserUtilitySurface) {
        if floatsUtilities {
            isFloatingSidebarPresented = true
        } else if columnVisibility == .detailOnly, !isFloatingSidebarPresented {
            showSidebar()
        }
        utilityPresentation.present(surface)
    }

    /// Utility shortcuts preserve the docked preference and toggle a floating sidebar when hidden.
    func toggleUtility(_ surface: BrowserUtilitySurface) {
        let floats = columnVisibility == .detailOnly || floatsUtilities
        if utilityPresentation.surface == surface,
            !floats || isFloatingSidebarPresented
        {
            utilityPresentation.dismiss(surface)
            if floats {
                isFloatingSidebarPresented = false
            }
        } else {
            if floats {
                isFloatingSidebarPresented = true
            }
            presentUtility(surface)
        }
    }

    func handleWebContentInteraction() {
        guard columnVisibility != .detailOnly || !isFloatingSidebarPresented else { return }
        utilityPresentation.handleInteraction(.webContent)
    }

    // MARK: - Actions - Command Palette

    func openLocation(_ address: String = "") {
        BrowserMoments.shared.begin(.commandBarOpen)
        commandPaletteMode = .editLocation(address)
    }

    /// Edits `address`, or puts the editor away when it is already showing,
    /// as pressing Open Location's keys again does.
    func toggleLocation(_ address: String) {
        if isEditingLocation {
            dismissCommandPalette()
        } else {
            openLocation(address)
        }
    }

    func presentCommandPalette() {
        BrowserCommandBarTiming.mark(.command)
        BrowserMoments.shared.begin(.commandBarOpen)
        commandPaletteMode = .newTab
    }

    /// New Tab opens the Command Bar, focuses a start page already shown, or
    /// closes a Command Bar it opened, so the same keys dismiss it.
    func openNewTab(isStartPageSelected: Bool) {
        // The same keys close a Command Bar they opened; over a Start Page it
        // closes into the page's own field below.
        if commandPaletteMode == .newTab, !isStartPageSelected {
            dismissCommandPalette()
            return
        }
        guard isStartPageSelected else {
            presentCommandPalette()
            return
        }
        commandPaletteMode = nil
        startPageFocusRequest &+= 1
    }

    func dismissCommandPalette() {
        if commandPaletteMode != nil { BrowserCommandBarTiming.mark(.closed) }
        commandPaletteMode = nil
    }

    // MARK: - Actions - Notices

    /// Shows `notice` at the top of this window, replacing any notice already
    /// there.
    func showNotice(_ notice: BrowserNotice) {
        notices.show(notice)
    }

    func showURLCopiedFeedback() {
        showNotice(.urlCopied)
    }

    func showPageZoomFeedback(_ label: String) {
        showNotice(.pageZoom(label))
    }
}

extension BrowserChromeState: BrowserStoreFirstObservable {}
