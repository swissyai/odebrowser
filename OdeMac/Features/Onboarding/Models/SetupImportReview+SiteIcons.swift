import Foundation

extension SetupImportReview {
    /// The images the tabs of each reviewed Space wear, open or archived, in
    /// the order of the review's Spaces, from `siteIcons`, the icons the
    /// source browser kept by page address.
    func tabImages(from siteIcons: [String: Data]) -> [[UUID: Data]] {
        guard !siteIcons.isEmpty else { return [] }
        return spaces.map { space in
            var images: [UUID: Data] = [:]
            for tab in space.source.tabs + space.source.archivedTabs.map(\.tab) {
                if let url = tab.url, let icon = siteIcons[url] { images[tab.id] = icon }
            }
            return images
        }
    }
}
