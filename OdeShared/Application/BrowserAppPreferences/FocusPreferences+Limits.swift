import Foundation

extension FocusPreferences {
    // MARK: - Static Variables

    /// The limits the site controls offer, in minutes a day.
    static let offeredMinutes = [15, 30, 60, 120]

    // MARK: - Actions - Limits

    /// The daily limit for `site`, or nil when it has none.
    func limit(for site: String?) -> SiteTimeLimit? {
        guard let site else { return nil }
        return limits.first { $0.site == site }
    }

    /// These preferences with `site` limited to `minutes` a day, or without a
    /// limit for it when `minutes` is nil. The core keeps one per site.
    func limiting(_ site: String, to minutes: Int?) -> FocusPreferences {
        var next = self
        next.limits.removeAll { $0.site == site }
        if let minutes { next.limits.append(SiteTimeLimit(site: site, minutesPerDay: minutes)) }
        return next
    }
}
