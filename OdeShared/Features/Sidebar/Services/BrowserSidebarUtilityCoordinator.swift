import Foundation

/// The archive, history, and downloads actions the sidebar's utility surfaces
/// perform, behind the one access guard they all share.
///
/// Every action re-reads the session at call time and refuses unless the Space
/// the caller named is still the selected, unlocked one it owns — the surfaces
/// hand out captured closures, and a Space can be reselected, relocked, deleted,
/// or have its profile replaced between the capture and the tap. Only the last
/// step of each action differs between the shells; that step comes from
/// `BrowserSidebarUtilityPlatformActions`.
@MainActor
struct BrowserSidebarUtilityCoordinator {
    // MARK: - Variables

    let browser: BrowserStore
    let downloadCenter: BrowserDownloadCenter
    let spaceAccess: BrowserSpaceAccessController
    let platformActions: BrowserSidebarUtilityPlatformActions

    var selectedDownloads: [DownloadState] {
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return [] }
        return downloadCenter.items(for: space.profileID)
    }

    var actions: BrowserUtilityListActions {
        BrowserUtilityListActions(
            restoreArchivedTab: restoreArchivedTab,
            keepArchivedTab: keepArchivedTab,
            openHistoryEntry: openHistoryEntry,
            keepHistoryEntry: keepHistoryEntry,
            removeHistoryEntry: removeHistoryEntry,
            removeHistorySite: removeHistorySite,
            readHistory: BrowserHistoryReader(core: browser.core, workspaceID: browser.family.workspaceID),
            downloadDestinations: platformActions.downloadDestinations,
            offersMoveToTrash: platformActions.trashFinishedDownload != nil,
            performDownloadAction: performDownloadAction,
            clearDownloads: clearDownloads
        )
    }

    // MARK: - Actions - Navigation

    /// Retained sidebar pages may navigate only for their current, unlocked Space/profile.
    func selectSurface(
        _ surface: BrowserUtilitySurface,
        matching assignment: BrowserSpaceRuntimeAssignment,
        in presentation: BrowserUtilityPresentationState
    ) {
        guard browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil else { return }
        presentation.present(surface, for: assignment.spaceID)
    }

    func dismissSurface(
        _ surface: BrowserUtilitySurface,
        matching assignment: BrowserSpaceRuntimeAssignment,
        in presentation: BrowserUtilityPresentationState
    ) {
        guard browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil else { return }
        presentation.dismiss(surface)
    }

    // MARK: - Actions - Records

    func acknowledgeDownloads(ifPresented surface: BrowserUtilitySurface?) {
        guard surface == .downloads, let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return }
        downloadCenter.acknowledgeItems(for: space.profileID)
    }

    private func restoreArchivedTab(
        _ tabID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard
            browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil,
            browser.restoreArchivedTab(tabID, matching: assignment)
        else { return }
        platformActions.selectRestoredTab(tabID)
    }

    private func keepArchivedTab(
        _ tabID: UUID,
        placement: TabPlacement,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard placement.isDurable,
            browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil
        else { return }
        browser.keepArchivedTab(tabID, placement: placement, matching: assignment)
    }

    private func openHistoryEntry(
        _ entry: HistoryPlace,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard
            browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil,
            let url = URL(string: entry.url)
        else { return }
        platformActions.openHistoryEntry(url, assignment)
    }

    private func keepHistoryEntry(
        _ entry: HistoryPlace,
        placement: TabPlacement,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil,
            let url = URL(string: entry.url)
        else { return }
        browser.openSessionTab(
            TabContent(address: url.absoluteString, view: nil, title: entry.title),
            in: assignment.spaceID, placement: placement, shouldSelect: false)
    }

    private func removeHistoryEntry(_ entry: HistoryPlace, matching assignment: BrowserSpaceRuntimeAssignment) {
        guard browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil else { return }
        browser.removeHistoryAddress(entry.url, in: assignment.spaceID)
    }

    private func removeHistorySite(_ entry: HistoryPlace, matching assignment: BrowserSpaceRuntimeAssignment) {
        guard browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil else { return }
        browser.removeHistorySite(entry.url, in: assignment.spaceID)
    }

    private func performDownloadAction(
        _ action: BrowserUtilityDownloadAction,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard let item = downloadItem(for: action, matching: assignment) else {
            return
        }
        action.perform(on: self, for: item, matching: assignment)
    }

    private func clearDownloads(matching assignment: BrowserSpaceRuntimeAssignment) {
        guard let space = browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess)
        else { return }
        downloadCenter.clearEnded(for: space.profileID)
    }

    private func downloadItem(
        for action: BrowserUtilityDownloadAction,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> DownloadState? {
        action.downloadItem(
            matching: assignment, in: browser, accessController: spaceAccess,
            itemsForProfile: downloadCenter.items(for:))
    }
}

// MARK: - Actions - Downloads

extension BrowserSidebarUtilityCoordinator: BrowserDownloadActionPerformer {
    func openDownload(_ item: DownloadState, in destination: BrowserUtilityDownloadDestination) {
        platformActions.openFinishedDownload(item, destination)
    }

    func retryDownload(_ item: DownloadState, matching assignment: BrowserSpaceRuntimeAssignment) {
        downloadCenter.retryAutomaticDownload(item.id, matching: assignment) { expectedAssignment in
            browser.unlockedSpace(matching: expectedAssignment, accessController: spaceAccess) != nil
        }
    }

    func pauseDownload(_ item: DownloadState) {
        downloadCenter.pause(item.id)
    }

    func resumeDownload(_ item: DownloadState) {
        downloadCenter.resume(item.id)
    }

    func cancelDownload(_ item: DownloadState) {
        platformActions.cancelDownload(item.id)
    }

    func clearDownload(_ item: DownloadState) {
        platformActions.clearDownload(item.id)
    }

    func trashDownload(_ item: DownloadState) {
        platformActions.trashFinishedDownload?(item)
    }
}
