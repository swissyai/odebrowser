import SwiftUI

/// The failure's symbol in Ode blue on a raised tile of the page's paper.
struct BrowserNavigationFailureStatusIcon: View {
    let symbolName: String
    let iconSize: CGFloat

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: OdeCornerScale.surface, style: .continuous)
        Image(systemName: symbolName)
            .font(
                .system(
                    size: iconSize * BrowserNavigationFailureMetrics.iconSymbolScale,
                    weight: .semibold
                )
            )
            .foregroundStyle(OdeBrandTheme.accentText)
            .frame(width: iconSize, height: iconSize)
            .background {
                tile.fill(OdeBrandTheme.surface)
                tile.strokeBorder(OdeBrandTheme.line, lineWidth: OdeLayout.hairline)
            }
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Offline and certificate") {
        HStack(spacing: 24) {
            BrowserNavigationFailureStatusIcon(symbolName: "wifi.slash", iconSize: 48)
            BrowserNavigationFailureStatusIcon(symbolName: "lock.trianglebadge.exclamationmark", iconSize: 48)
        }.padding()
    }
#endif
