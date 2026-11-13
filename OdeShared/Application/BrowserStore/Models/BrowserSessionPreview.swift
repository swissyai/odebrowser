import Foundation

/// A session no workspace holds, as the previews draw it: its Spaces as the
/// read model would hold them, and the images their tabs would wear. Nothing
/// the core publishes ever reaches it.
@MainActor
struct BrowserSessionPreview {
    // MARK: - Variables

    let spaces: [SpaceModel]
    let favicons: FaviconAssets

    // MARK: - Initializers

    /// The session an import would leave: each tab it keeps wears the image
    /// `images` holds for it, or for the tab it was copied from, and each tab
    /// it brings wears the one `imported` holds for the tab it came from, by
    /// the position of its Space in the import, or none.
    init(importing preview: ImportedWorkspace, images: FaviconAssets, imported offered: [[UUID: Data]] = []) {
        let copies = Dictionary(preview.copied.map { ($0.copyTabID, $0.sourceTabID) }) { first, _ in first }
        let imported = Set(preview.imported.map(\.tabID))
        var kept: [UUID: Data] = [:]
        for space in preview.session.spaces {
            for tab in space.tabs where !imported.contains(tab.id) {
                kept[tab.id] = images.image(of: copies[tab.id] ?? tab.id)
            }
        }
        for tab in preview.imported where offered.indices.contains(tab.source) {
            kept[tab.tabID] = offered[tab.source][tab.sourceTabID]
        }
        spaces = preview.session.spaces.map(SpaceModel.init)
        favicons = FaviconAssets()
        favicons.adopt(kept, holding: { _ in true })
    }

    // MARK: - Actions - Reading

    /// The Space the session holds with this identity.
    func space(id: UUID) -> SpaceModel? {
        spaces.first { $0.id == id }
    }
}
