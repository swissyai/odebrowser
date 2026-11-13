import Foundation

/// The site icons another browser kept for the pages an import brings, by
/// page address, read while the browser's folder is open to Ode: from each
/// profile's Chromium `Favicons` or Mozilla `favicons.sqlite` database, a
/// snapshot of it since the browser may be running. Each icon is the largest
/// the browser kept, ready for a tab to wear; a page whose icon Ode cannot
/// read is left for the lookup that finds icons of pages no tab has loaded.
enum BrowserImportedSiteIcons {
    // MARK: - Static Variables

    /// The most icon bytes one import carries.
    static let maximumByteCount = 64 * 1_024 * 1_024

    // MARK: - Actions - Reading

    /// The icons the profile folders `profileFolders` keep for the open and
    /// archived tabs of `spaces`, the first profile's first.
    static func read(for spaces: [SpaceState], in profileFolders: [String]) -> [String: Data] {
        var wanted = Set(
            spaces.flatMap { space in space.tabs.compactMap(\.url) + space.archivedTabs.compactMap(\.tab.url) }
                .filter { $0.hasPrefix("https://") || $0.hasPrefix("http://") })
        var icons: [String: Data] = [:]
        var byteCount = 0
        for folder in profileFolders where !wanted.isEmpty {
            let profile = URL(fileURLWithPath: folder, isDirectory: true)
            let found =
                ChromiumFaviconDatabase(profileFolder: profile)?.icons(for: Array(wanted))
                ?? MozillaFaviconDatabase(profileFolder: profile)?.icons(for: Array(wanted)) ?? [:]
            for (pageURL, icon) in found where byteCount + icon.count <= maximumByteCount {
                icons[pageURL] = icon
                byteCount += icon.count
                wanted.remove(pageURL)
            }
        }
        return icons
    }
}
