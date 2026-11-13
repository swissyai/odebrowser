import SwiftUI

struct BrowserOdeImportContent: View {
    let space: SpaceModel
    let favicons: FaviconAssets
    let matchedTabIDs: Set<UUID>
    var extensions: [ImportExtension] = []
    var extensionIcons: [String: NSImage] = [:]
    @Environment(OdeCore.self) private var core: OdeCore?

    /// No window shows an imported Space yet, so it highlights the tab the
    /// core would show first.
    private var highlightedTabID: UUID? { core?.fallbackTabID(in: space) }

    var body: some View {
        VStack(spacing: 0) {
            BrowserOdeImportChrome(space: space, highlightedTabID: highlightedTabID)

            if !extensions.isEmpty {
                BrowserImportSidebarExtensionStrip(extensions: extensions, icons: extensionIcons)
                    .padding(.horizontal, 10)
                    .padding(.top, 7)
            }

            if !space.pinnedTabs.isEmpty {
                BrowserOdeImportPinnedGrid(
                    space: space,
                    favicons: favicons,
                    matchedTabIDs: matchedTabIDs,
                    highlightedTabID: highlightedTabID
                )
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            BrowserOdeImportSpaceHeader(space: space)
            BrowserOdeImportTabList(
                space: space,
                favicons: favicons,
                matchedTabIDs: matchedTabIDs,
                highlightedTabID: highlightedTabID
            )
            BrowserOdeImportSpaceSwitcher(space: space)
        }
    }
}
