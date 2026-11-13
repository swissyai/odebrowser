import Foundation

extension BrowserPagePool {
    // MARK: - Actions - Boosts

    /// Gives `page` its Space's Boosts and the way to keep the person's edits
    /// in that Space, which the window that owns the Space's profile keeps.
    func connectBoosts(of page: BrowserPage, in space: SpaceModel, routing: BrowserPageWindowRouting) {
        let spaceID = space.id
        page.boost.save = { [weak routing] boost in
            if routing?.pool?.browser.setSiteBoost(boost, in: spaceID) == true {
                BrowserGettingStartedMoves.record(.boost)
            }
        }
        page.boost.remove = { [weak routing] site in routing?.pool?.browser.removeSiteBoost(for: site, in: spaceID) }
        page.boost.follow(space.settings.boosts)
        page.boost.followFocus(
            BrowserFocusFeeds.stylesheets(hidingFeeds: BrowserAppPreferenceStore.shared.focus.hidesFeeds))
    }

    /// Gives every page its Space's Boosts as the window's workspace keeps
    /// them now, and what Focus hides.
    func reconcileBoosts() {
        let boosts = Dictionary(
            uniqueKeysWithValues: (browser.workspaceModel?.spaces.models ?? []).map { ($0.id, $0.settings.boosts) })
        // A private window's pages stay quiet too: Focus is the person's, not a Space's.
        let focus = BrowserFocusFeeds.stylesheets(hidingFeeds: BrowserAppPreferenceStore.shared.focus.hidesFeeds)
        for runtime in host.runtimes.values {
            runtime.page.boost.follow(boosts[runtime.page.spaceID] ?? nil)
            runtime.page.boost.followFocus(focus)
        }
        for lease in host.liveTransientLeases {
            lease.page?.boost.follow(boosts[lease.spaceID] ?? nil)
            lease.page?.boost.followFocus(focus)
        }
    }
}
