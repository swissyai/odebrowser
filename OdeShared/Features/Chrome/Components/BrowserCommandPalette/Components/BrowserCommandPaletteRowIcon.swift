import SwiftUI

/// What stands for a row at its start, straight on the panel: the tab's or
/// site's icon, the Space's tile, a muted magnifying glass for a search
/// suggestion, the search provider's logo, or the row's symbol.
struct BrowserCommandPaletteRowIcon: View {
    let model: BrowserCommandPaletteModel
    let row: PaletteRow

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let tab = model.tab(for: row) {
                TabStateFaviconView(
                    tab: tab,
                    favicons: model.browser.core.state.favicons,
                    profileID: model.space?.profileID,
                    size: BrowserCommandPaletteMetrics.rowFaviconSize
                )
                .overlay(alignment: .bottomTrailing) {
                    TabEngineBadge(
                        tabID: tab.id,
                        scale: BrowserCommandPaletteMetrics.rowFaviconSize / TabFaviconMetrics.defaultSize)
                }
            } else if row.kind == .space, let space = row.subjectID.flatMap(model.browser.spaceModel) {
                BrowserSpaceIcon(
                    space: space, form: .tile, size: BrowserCommandPaletteMetrics.rowIconContainerSize)
            } else if row.kind == .searchSuggestion {
                // A suggestion is one more search with the engine the first
                // row already shows, so it wears a quiet glass, not the logo.
                Image(systemName: "magnifyingglass")
                    .font(.system(size: BrowserCommandPaletteMetrics.rowSymbolPointSize, weight: .medium))
                    .foregroundStyle(.paletteDetail)
            } else if let provider = model.searchProvider(for: row) {
                BrowserSearchProviderIcon(
                    provider: provider,
                    profileID: model.space?.profileID,
                    size: BrowserCommandPaletteMetrics.rowFaviconSize
                )
            } else {
                Image(systemName: row.symbol)
                    .font(
                        .system(
                            size: BrowserCommandPaletteMetrics.rowSymbolPointSize,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.paletteDetail)
            }
        }
        .frame(
            width: BrowserCommandPaletteMetrics.rowIconContainerSize,
            height: BrowserCommandPaletteMetrics.rowIconContainerSize
        )
        // Site icons sit on the panel, not on a sidebar.
        .environment(
            \.browserFaviconGroundLuminance,
            colorScheme == .dark
                ? BrowserCommandPaletteMetrics.darkIconGroundLuminance
                : BrowserCommandPaletteMetrics.lightIconGroundLuminance
        )
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Result icons") {
        let model = BrowserCommandPalettePreviewFixture.model(query: "swift")
        HStack(spacing: 20) {
            BrowserCommandPaletteRowIcon(model: model, row: BrowserCommandPalettePreviewFixture.intentRow)
            BrowserCommandPaletteRowIcon(model: model, row: BrowserCommandPalettePreviewFixture.tabRow)
            BrowserCommandPaletteRowIcon(model: model, row: BrowserCommandPalettePreviewFixture.commandRow)
        }.padding()
    }
#endif
