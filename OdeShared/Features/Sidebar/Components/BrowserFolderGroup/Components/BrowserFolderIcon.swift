import SwiftUI

/// The folder's symbol, in the same column the rows below give their favicons.
struct BrowserFolderIcon: View {
    let folder: FolderStateModel
    let isExpanded: Bool
    let metrics: BrowserFolderHeaderMetrics
    private var iconOnly: Bool { BrowserDeviceAppearanceStore.shared.foldersIconOnly }

    var body: some View {
        BrowserFolderArtwork(symbol: folder.displaySymbol, color: folder.displayColor, isExpanded: isExpanded)
            .modifier(
                BrowserFolderIconColumn(
                    metrics: metrics,
                    isExpanded: isExpanded
                        && !(iconOnly && BrowserFolderArtwork.customGlyph(for: folder.displaySymbol) != nil)
                )
            )
            .accessibilityHidden(true)
    }
}

/// Applies the saved folder artwork preference to the shared drawing.
struct BrowserFolderArtwork: View {
    let symbol: String
    let color: BrandColor
    var isExpanded = false
    private var iconOnly: Bool { BrowserDeviceAppearanceStore.shared.foldersIconOnly }
    private var tintsTitle: Bool { BrowserDeviceAppearanceStore.shared.foldersTintTitle }

    var body: some View {
        BrowserFolderArtworkContent(
            symbol: symbol, color: color, isExpanded: isExpanded, iconOnly: iconOnly, tintsTitle: tintsTitle)
    }

    static func customGlyph(for symbol: String) -> Text? {
        BrowserFolderArtworkContent.customGlyph(for: symbol)
    }
}

/// Holds the symbol in its column, and sizes it where the shell reads the row
/// from further away than a desk.
private struct BrowserFolderIconColumn: ViewModifier {
    /// How much wider than the favicons' column the drawing and its open
    /// front stand. The drawing starts at the column's leading edge.
    private static let overhang: CGFloat = 6

    let metrics: BrowserFolderHeaderMetrics
    let isExpanded: Bool
    private var iconScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    func body(content: Content) -> some View {
        let scale = BrowserSidebarDensity(iconScale).scale
        content
            .font(.system(size: ((metrics.iconGlyphSize ?? 16) + 2) * scale, weight: metrics.iconGlyphWeight))
            // Overhangs the favicons' column evenly, so it is centered on the
            // favicons and the title keeps a tab title's column, which the
            // open front never moves. The bottom hinge lowers its optical
            // center.
            .offset(x: -Self.overhang / 2 * scale, y: (isExpanded ? -1.5 : -0.5) * scale)
            .frame(width: metrics.iconWidth * scale)
    }
}
