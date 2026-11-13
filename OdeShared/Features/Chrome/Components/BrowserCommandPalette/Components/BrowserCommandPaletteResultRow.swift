import SwiftUI

struct BrowserCommandPaletteResultRow: View {
    let model: BrowserCommandPaletteModel
    let item: BrowserCommandPaletteItem
    /// The row names its kind at its end, as the blended layout shows it.
    var namesKind = false

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isSelected: Bool { model.selectedResultIndex == item.index }

    var body: some View {
        if capabilities.supportsTouch, horizontalSizeClass == .compact {
            rowButton.accessibilityLabel(compactAccessibilityLabel)
        } else {
            rowButton
        }
    }

    private var compactAccessibilityLabel: Text {
        let detail = BrowserCommandPaletteRowLabel.detail(for: item.row)
        var label = Text(verbatim: item.row.title)
        if !detail.isEmpty { label = label + Text(verbatim: ", \(detail)") }
        if let action = item.row.kind.action { label = label + Text(verbatim: ", ") + Text(action) }
        if isSelected, let opening = model.selectedOpening.title {
            label = label + Text(verbatim: ", ") + Text(opening)
        }
        return label
    }

    private var rowButton: some View {
        Button {
            model.activate(item.row)
        } label: {
            HStack(spacing: BrowserCommandPaletteMetrics.rowSpacing) {
                BrowserCommandPaletteRowIcon(model: model, row: item.row)

                BrowserCommandPaletteRowLabel(model: model, row: item.row)
                    .layoutPriority(1)

                Spacer(minLength: BrowserCommandPaletteMetrics.rowSpacing)

                BrowserCommandPaletteRowTrailing(
                    model: model, row: item.row, isSelected: isSelected, namesKind: namesKind)
            }
        }
        .buttonStyle(
            BrowserCommandPaletteRowButtonStyle(
                isSelected: isSelected
            )
        )
        .accessibilityValue(model.engineBadge(for: item.row).map { Text($0.pageDescription) } ?? Text(verbatim: ""))
        .accessibilityHint(item.row.reason.map { Text($0.text) } ?? Text(verbatim: ""))
        .accessibilityIdentifier("command-palette-result-\(item.index)")
        .browserCommandPaletteHoverSelection(model: model, index: item.index)
    }
}

#if DEBUG
    #Preview("Tab and command results") {
        let model = BrowserCommandPalettePreviewFixture.model(query: "swift")
        VStack(spacing: 4) {
            BrowserCommandPaletteResultRow(model: model, item: BrowserCommandPalettePreviewFixture.tabItem)
            BrowserCommandPaletteResultRow(model: model, item: BrowserCommandPalettePreviewFixture.commandItem)
        }.padding().frame(width: 600)
    }
#endif
