import Foundation

extension BrowserPagePool {
    // MARK: - Actions - Tab previews

    /// Starts reading the previews of the workspace's pinned and saved tabs,
    /// from whichever of its windows is still open, skipping the Spaces
    /// `spaceAccess` keeps locked. A private window previews nothing.
    func startTabPreviews(spaceAccess: BrowserSpaceAccessController) {
        guard !browser.isPrivateBrowsing else { return }
        let previews = runtimeStore.tabPreviews
        previews.sources = { [weak runtimeStore, weak spaceAccess] in
            guard let spaceAccess, let pool = runtimeStore?.registeredPools.first(where: \.isWindowOpen) else {
                return []
            }
            return pool.tabPreviewSources(isLocked: spaceAccess.isLocked)
        }
        previews.preferences = { [weak browser] in
            browser?.workspaceModel?.appPreferences?.tabPreviews ?? .default
        }
        previews.start()
    }

    /// The pinned and saved tabs of the workspace's Spaces that `isLocked`
    /// leaves open, each with its page while the tab is awake and done
    /// loading.
    func tabPreviewSources(isLocked: (SpaceModel) -> Bool) -> [BrowserTabPreviewCenter.Source] {
        browser.spaceModels.filter { !isLocked($0) }.flatMap { space in
            space.tabs.models.compactMap { tab -> BrowserTabPreviewCenter.Source? in
                guard tab.placement.isDurable else { return nil }
                let page = residentPage(
                    matching: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID))
                guard let url = (page?.live.url ?? tab.url).flatMap(URL.init(string:)) else { return nil }
                return BrowserTabPreviewCenter.Source(
                    tabID: tab.id, url: url, document: page?.live.isLoading == false ? page?.previewDocument : nil,
                    generation: page?.completedNavigationCount ?? 0)
            }
        }
    }

    /// The preview of the tab `assignment` names, while its site shows one.
    func tabPreview(matching assignment: BrowserTabRuntimeAssignment) -> BrowserTabPreview? {
        runtimeStore.tabPreviews.preview(of: assignment.tabID, at: tabPreviewURL(matching: assignment))
    }

    /// The site whose preview the tab `assignment` names shows, while it
    /// shows one.
    func tabPreviewSite(matching assignment: BrowserTabRuntimeAssignment) -> BrowserTabPreviewSite? {
        runtimeStore.tabPreviews.site(for: tabPreviewURL(matching: assignment))
    }

    /// Shows the tab `assignment` names in this window and opens `item` in
    /// it, when the item opens on the tab's own site; for nil, or an item
    /// that opens nowhere, only shows the tab.
    func openTabPreviewItem(_ item: BrowserTabPreview.Item?, in assignment: BrowserTabRuntimeAssignment) {
        guard browser.shownSpace?.id == assignment.spaceID else { return }
        let site = tabPreviewURL(matching: assignment).map(BrowserTabPreviewCenter.origin(of:))
        browser.selectTab(assignment.tabID)
        select()
        guard let link = item?.link, BrowserTabPreviewCenter.origin(of: link) == site else { return }
        Task { @MainActor [weak self] in
            // Showing a sleeping tab wakes its page a moment later.
            for _ in 0..<40 {
                if let page = self?.residentPage(matching: assignment) {
                    page.corePage.load(link)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Where the tab `assignment` names is now: its page's address while it
    /// has one, else the tab's.
    private func tabPreviewURL(matching assignment: BrowserTabRuntimeAssignment) -> URL? {
        guard
            let tab = browser.spaceModel(
                matching: BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID)
            )?.tabs.model(assignment.tabID)
        else { return nil }
        return (residentPage(matching: assignment)?.live.url ?? tab.url).flatMap(URL.init(string:))
    }
}
