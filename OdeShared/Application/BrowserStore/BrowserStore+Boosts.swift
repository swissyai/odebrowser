import Foundation

// MARK: - Boosts

extension BrowserStore {
    /// Keeps `boost` as the Space's Boost for its site, in place of the one
    /// it had. Answers whether the session changed.
    @discardableResult
    func setSiteBoost(_ boost: SiteBoost, in spaceID: UUID) -> Bool {
        sendSpaceSettings(
            SetSiteBoost(workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID, boost: boost))
    }

    /// Forgets the Space's Boost for `site`. Answers whether the session
    /// changed.
    @discardableResult
    func removeSiteBoost(for site: String, in spaceID: UUID) -> Bool {
        sendSpaceSettings(
            RemoveSiteBoost(workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID, site: site))
    }
}
