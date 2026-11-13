import Foundation

/// The mutations a sidebar row performs on the tabs of one Space.
///
/// Both shells ask for the same work behind the same guard: the Space this
/// instance was built for must still be the selected, unlocked one, and the tab
/// must still be in it. What the shells do not share is what the page layer
/// owes once the session changes — the windowed shell keeps a pool of cards in
/// step, the compact shell's single page follows the session on its own — so
/// the page-facing steps arrive as closures each shell binds in its own
/// convenience initializer.
@MainActor
struct BrowserSidebarTabActions {
    let assignment: BrowserSpaceRuntimeAssignment
    private let reorderState: BrowserSidebarReorderState
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    /// Brings the page layer back in step with a session this type just
    /// rewrote. The windowed shell reconciles its pool and re-presents the
    /// selection; the compact shell has nothing to do.
    private let syncPagesAfterMutation: @MainActor () -> Void

    /// Asks a resident page for a fresh favicon. `nil` when the tab holds no
    /// page, has moved, or the page cannot produce one.
    private let pullFavicon:
        @MainActor (
            UUID,
            BrowserSpaceRuntimeAssignment
        ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)?

    init(
        assignment: BrowserSpaceRuntimeAssignment,
        browser: BrowserStore,
        reorderState: BrowserSidebarReorderState,
        spaceAccess: BrowserSpaceAccessController,
        syncPagesAfterMutation: @escaping @MainActor () -> Void,
        pullFavicon:
            @escaping @MainActor (
                UUID,
                BrowserSpaceRuntimeAssignment
            ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)?
    ) {
        self.assignment = assignment
        self.browser = browser
        self.reorderState = reorderState
        self.spaceAccess = spaceAccess
        self.syncPagesAfterMutation = syncPagesAfterMutation
        self.pullFavicon = pullFavicon
    }

    /// Replaces a tab's favicon with whatever its page reports now.
    ///
    /// The ownership check runs on both sides of the pull on purpose: a Space
    /// can be reselected, relocked, or have its profile replaced while the
    /// request is in flight, and an icon written after that would land on a tab
    /// this sidebar no longer speaks for.
    @discardableResult
    func pullNewIcon(for tabID: UUID) async -> Bool {
        guard ownsUnlockedTab(tabID),
            let pulled = await pullFavicon(tabID, assignment),
            ownsUnlockedTab(tabID)
        else { return false }
        return browser.setTabFavicon(
            pulled.data,
            iconAccent: pulled.iconAccent,
            for: tabID,
            matching: assignment
        )
    }

    /// Closes the Space's current tabs, leaving its pinned and saved tabs be.
    @discardableResult
    func clearCurrentTabs() -> Bool {
        guard
            browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil,
            browser.clearCurrentTabs(matching: assignment)
        else { return false }
        syncPagesAfterMutation()
        return true
    }

    /// The tabs Tidy may group: those at the top of the Space's current
    /// section, in sidebar order. Tabs in a folder or a split, and pinned and
    /// saved tabs, stay out.
    func tidyableTabs() -> [BrowserTidyToday.Tab] {
        guard
            let space = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess)
        else { return [] }
        return space.sidebar.section(.current).rows.compactMap { row in
            guard !row.kind.opensList, !row.kind.groupsTabs, let tab = space.tabs.model(row.id),
                tab.placement == .current, !tab.isStartPage
            else { return nil }
            return BrowserTidyToday.Tab(id: tab.id, title: tab.shownTitle, address: tab.address)
        }
    }

    /// Files each accepted group into a new folder in the Space's current
    /// section, then closes the duplicates the person chose to close. A tab
    /// that has left the current section since the proposal is left alone.
    @discardableResult
    func tidyCurrentTabs(into groups: [BrowserTidyToday.Group], closing duplicates: [BrowserTidyToday.Tab]) -> Bool {
        guard
            let space = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess)
        else { return false }
        let isCurrent = { (id: UUID) in space.tabs.model(id)?.placement == .current }
        var changed = false
        for group in groups {
            let tabIDs = group.tabs.map(\.id).filter(isCurrent)
            guard tabIDs.count >= 2,
                browser.createTabFolder(tabIDs, titled: group.name, matching: assignment) != nil
            else { continue }
            changed = true
        }
        for tab in duplicates where isCurrent(tab.id) {
            guard browser.closeTab(tab.id, matching: assignment) else { continue }
            changed = true
        }
        guard changed else { return false }
        syncPagesAfterMutation()
        return true
    }

    /// Routes an empty-background gesture through the host's existing New Tab
    /// command. Recheck ownership when the gesture ends, after any Space change.
    @discardableResult
    func openNewTab(_ command: () -> Void) -> Bool {
        guard !reorderState.isDragging,
            browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil
        else { return false }
        command()
        return true
    }

    private func ownsUnlockedTab(_ tabID: UUID) -> Bool {
        guard
            let space = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess)
        else { return false }
        return space.shownTab(tabID) != nil
    }
}
