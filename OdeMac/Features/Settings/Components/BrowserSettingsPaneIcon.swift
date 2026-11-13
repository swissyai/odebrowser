import SwiftUI

/// A settings pane's icon: its symbol, filled, in white on a rounded tile of
/// the pane's Ode colour. About wears Ode's mark on its own paper instead.
struct BrowserSettingsPaneIcon: View {
    // MARK: - Static Variables

    /// The side of a tile in the Settings sidebar, which a Space's tile
    /// beside it shares.
    static let sidebarSide: CGFloat = 20
    /// The side of the tile beside a page's title.
    static let titleSide: CGFloat = 24

    // MARK: - Variables

    let destination: BrowserSettingsDestination
    var side: CGFloat = Self.sidebarSide

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if destination == .about {
                OdeMark(placement: .onCanvas, finish: .flat)
                    .background(OdeBrandTheme.surface, in: shape)
                    .overlay { shape.strokeBorder(OdeBrandTheme.line, lineWidth: OdeLayout.hairline / 2) }
            } else {
                Image(systemName: destination.symbol)
                    .symbolVariant(.fill)
                    .font(.system(size: side * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: side, height: side)
                    .background(destination.tile, in: shape)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// The corner scale's inset, held to under a third of the side so a
    /// small tile stays a rounded square.
    private var cornerRadius: CGFloat { min(OdeCornerScale.inset, side * 0.3) }
}

#if DEBUG
    #Preview("Every pane") {
        HStack(spacing: OdeSpacing.small) {
            ForEach(BrowserSettingsDestination.all) { destination in
                BrowserSettingsPaneIcon(destination: destination)
            }
        }
        .padding()
    }
#endif
