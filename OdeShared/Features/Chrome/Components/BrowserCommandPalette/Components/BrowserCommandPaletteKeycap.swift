import SwiftUI

/// A key the Command Bar names, such as Tab beside the field or the arrow at
/// a row's end, on a small keycap in a faint tone of the current foreground,
/// so it reads on the panel and on a selected row alike.
struct BrowserCommandPaletteKeycap<Label: View>: View {
    @ViewBuilder let label: Label

    var body: some View {
        label
            .font(.callout.weight(.medium))
            .padding(.horizontal, BrowserCommandPaletteMetrics.keycapHorizontalPadding)
            .frame(
                minWidth: BrowserCommandPaletteMetrics.keycapMinimumSide,
                minHeight: BrowserCommandPaletteMetrics.keycapMinimumSide
            )
            .background(
                .foreground.opacity(BrowserCommandPaletteMetrics.keycapBackgroundOpacity),
                in: .rect(cornerRadius: BrowserCommandPaletteMetrics.shortcutCornerRadius, style: .continuous))
    }
}

#if DEBUG
    #Preview("Keycaps") {
        HStack {
            BrowserCommandPaletteKeycap { Text(verbatim: "Tab") }
            BrowserCommandPaletteKeycap { Image(systemName: "arrow.right") }
        }.padding()
    }
#endif
