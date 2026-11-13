import SwiftUI

/// A row the palette leads with or runs as typed: the best match, the
/// address or search for the text, a search provider, a calculation or a pasted
/// address. Its end says where Return opens it.
struct BrowserCommandPaletteIntentRow: View {
    let model: BrowserCommandPaletteModel
    let item: BrowserCommandPaletteItem

    private var isSelected: Bool { model.selectedResultIndex == item.index }

    var body: some View {
        Button {
            model.activate(item.row)
        } label: {
            HStack(spacing: BrowserCommandPaletteMetrics.rowSpacing) {
                BrowserCommandPaletteRowIcon(model: model, row: item.row)

                BrowserCommandPaletteRowLabel(model: model, row: item.row)

                Spacer(minLength: BrowserCommandPaletteMetrics.rowSpacing)

                BrowserCommandPaletteRowTrailing(model: model, row: item.row, isSelected: isSelected)
            }
        }
        .buttonStyle(
            BrowserCommandPaletteRowButtonStyle(
                isSelected: isSelected
            )
        )
        .accessibilityLabel(Text(verbatim: item.row.title))
        .accessibilityValue(Text(verbatim: item.row.subtitle))
        .accessibilityHint(item.row.reason.map { Text($0.text) } ?? Text(verbatim: ""))
        .accessibilityIdentifier("command-palette-primary-action")
        .browserCommandPaletteHoverSelection(model: model, index: item.index)
    }
}

#if DEBUG
    #Preview("Search intent") {
        BrowserCommandPaletteIntentRow(
            model: BrowserCommandPalettePreviewFixture.model(query: "swift"),
            item: BrowserCommandPalettePreviewFixture.intentItem
        )
        .padding().frame(width: 600)
    }
#endif
