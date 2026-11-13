import SwiftUI

struct SpaceSidebarUtilityContent: View {
    // MARK: - Variables

    let surface: BrowserUtilitySurface
    let selectSurface: (BrowserUtilitySurface) -> Void
    let backToTabs: () -> Void
    let space: SpaceModel
    let favicons: FaviconAssets
    @Binding var searchText: String
    @Binding var filter: BrowserUtilityListFilter
    let commandSurfaceNamespace: Namespace.ID
    let downloads: [DownloadState]
    let actions: BrowserUtilityListActions
    let dismissOnBlankSpace: () -> Void
    let clearHistory: () -> Void
    var searchFocusRequest = 0
    var consumeSearchFocusRequest: @MainActor (Int, BrowserUtilitySurface) -> Bool = { _, _ in false }

    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    private var clearDownloads: (() -> Void)? {
        guard let clear = actions.clearDownloads else { return nil }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        return { clear(assignment) }
    }

    var body: some View {
        if isSelected != false {
            BrowserUtilityNavigationHeader(surface: surface, select: selectSurface, backToTabs: backToTabs)
                .padding(.horizontal, BrowserSidebarMetrics.layerInset)
                .padding(.bottom, OdeSpacing.small)

            BrowserUtilitySearchToolbar(
                surface: surface,
                searchText: $searchText,
                filter: $filter,
                morphNamespace: commandSurfaceNamespace,
                morph: .utilitySearch(spaceID: space.id),
                clearHistory: clearHistory,
                clearDownloads: clearDownloads,
                canClearDownloads: downloads.contains(where: BrowserDownloadCenter.isClearable),
                focusRequest: searchFocusRequest,
                consumeFocusRequest: consumeSearchFocusRequest
            )
            .padding(.horizontal, BrowserSidebarMetrics.layerInset)
            .padding(.bottom, OdeSpacing.extraSmall)
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            BrowserUtilityListContent(
                surface: surface,
                space: space,
                downloads: downloads,
                searchText: searchText,
                filter: filter,
                actions: actions,
                dismissOnBlankSpace: dismissOnBlankSpace,
                favicons: favicons
            )
            // A section switch cancels preparation and discards that section's paging/error state.
            .id(surface)
            .transition(.opacity)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
}
