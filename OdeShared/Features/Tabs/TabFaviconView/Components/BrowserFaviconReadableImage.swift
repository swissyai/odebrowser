import SwiftUI

/// A decoded site icon drawn so it reads on its ground: as the site made it
/// while it does, otherwise a monochrome mark inverted or an icon with color
/// on a small plate of the opposite lightness.
struct BrowserFaviconReadableImage: View {
    let rendered: BrowserFaviconRenderedImage
    let size: CGFloat

    @Environment(\.browserFaviconGroundLuminance) private var groundLuminance
    @Environment(\.spaceColorRoles) private var spaceColorRoles
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let treatment =
            rendered.tone.map {
                BrowserFaviconTreatment.choose(for: $0, groundLuminance: ground)
            } ?? .asIs
        switch treatment {
        case .inverted where rendered.invertedImage != nil:
            icon(rendered.invertedImage ?? rendered.image)
        case .plated(let lightPlate):
            icon(rendered.image)
                .padding(size * TabFaviconMetrics.plateInsetRatio)
                .background(
                    lightPlate ? TabFaviconMetrics.lightPlate : TabFaviconMetrics.darkPlate,
                    in: .rect(cornerRadius: size * TabFaviconMetrics.plateCornerRatio, style: .continuous)
                )
        default:
            icon(rendered.image)
        }
    }

    private func icon(_ image: Image) -> some View {
        image
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .clipShape(
                .rect(cornerRadius: TabFaviconMetrics.cornerRadius(for: size))
            )
    }

    /// What the icon is drawn on: what the surface says, else its Space's
    /// sidebar, else the appearance's own ground.
    private var ground: Double {
        groundLuminance
            ?? spaceColorRoles?.applying(in: colorScheme)?.sidebar.relativeLuminance
            ?? (colorScheme == .dark
                ? TabFaviconMetrics.darkGroundLuminance : TabFaviconMetrics.lightGroundLuminance)
    }
}
