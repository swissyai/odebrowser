import Foundation

extension TabPreviewPreferences {
    // MARK: - Actions - Sites

    /// Whether a pinned or saved tab on `site` shows its preview.
    func showsPreviews(on site: String) -> Bool {
        showsPreviews && !sitesWithoutPreviews.contains(site)
    }

    /// These preferences with `site`'s previews on or off. The core spells
    /// and orders the sites when it keeps them.
    func settingPreviews(_ isOn: Bool, on site: String) -> TabPreviewPreferences {
        var next = self
        next.sitesWithoutPreviews.removeAll { $0 == site }
        if !isOn { next.sitesWithoutPreviews.append(site) }
        return next
    }
}
