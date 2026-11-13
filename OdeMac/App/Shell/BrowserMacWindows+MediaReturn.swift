import AppKit

/// Back to Tab: from a player in any window, to the tab that plays.
extension BrowserMacWindows {
    // MARK: - Actions - Media

    /// Where Back to Tab from `sourceWindowID` takes the person for `owner`,
    /// or nil when no open browser window holds the tab.
    func mediaReturnRoute(
        to owner: BrowserTabRuntimeAssignment, from sourceWindowID: UUID?
    ) -> BrowserMediaReturnRoute? {
        let models = browserWindowModels
        guard
            let space = models.lazy.compactMap({ $0.browser.spaceModel(matching: owner.spaceAssignment) }).first
        else { return nil }
        return BrowserMediaReturnRoute.resolve(
            owner: owner,
            fromWindow: sourceWindowID,
            windows: models.map { model in
                BrowserMediaReturnRoute.Window(
                    id: model.id,
                    holdsTab: model.browser.spaceModel(matching: owner.spaceAssignment)?.tabs.contains(owner.tabID)
                        == true,
                    presentsTab: model.pages.presentedTabIDs.contains(owner.tabID),
                    showsSpace: model.browser.selectedSpaceID == owner.spaceID)
            },
            isSpaceLocked: spaceAccess.isLocked(space)
        )
    }

    /// Goes back to the tab `owner` names from the window `sourceWindowID`:
    /// unlocks its Space, shows the tab, and brings its window forward when
    /// it is another one. The person's own click asks for this, so bringing a
    /// window forward is theirs to ask.
    func returnToPlayingTab(_ owner: BrowserTabRuntimeAssignment, from sourceWindowID: UUID?) async {
        guard let route = mediaReturnRoute(to: owner, from: sourceWindowID),
            let model = browserWindowModel(route.windowID),
            let space = model.browser.spaceModel(matching: owner.spaceAssignment)
        else { return }
        if route.unlocksSpace, !(await spaceAccess.unlock(space)) { return }
        model.browser.selectSpace(route.spaceID)
        guard model.browser.activateSessionTab(route.tabID, in: route.spaceID) else { return }
        model.pages.select()
        if route.bringsWindowForward {
            open(.reopening(route.windowID), activation: .key)
        }
    }

    /// Back to Playing Tab from the menu: the newest session that plays, in
    /// the browser window the person is in.
    func returnToPlayingTab(in sessions: [BrowserMediaSessionSnapshot]) async {
        guard let session = BrowserMediaReturnRoute.target(in: sessions) else { return }
        await returnToPlayingTab(session.owner, from: activeBrowserWindow.flatMap(browserWindowID(of:)))
    }

    /// The browser windows open over the person's Spaces and torn-off tabs,
    /// in the order they opened.
    private var browserWindowModels: [BrowserMacWindowModel] {
        openWindows.compactMap { entry in
            browserWindowID(of: entry.window).flatMap(browserWindowModel)
        }
    }
}
