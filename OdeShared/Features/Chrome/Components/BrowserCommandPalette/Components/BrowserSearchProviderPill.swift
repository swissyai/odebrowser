import SwiftUI

/// A search provider's pill, as the Command Bar shows it once Tab enters the
/// provider: its name on a solid capsule of its brand color, in white or
/// near-black text, whichever reads (``BrowserSearchProviderFill``), with a
/// soft glow of the color around it. A scope with a color of its own, such as
/// Ode Help, shows the same way. Reduce Transparency and Increase Contrast
/// keep the pill solid and draw no glow.
struct BrowserSearchProviderPill: View {
    let title: String
    let color: BrandColor

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(provider: SearchProvider) {
        self.init(title: provider.title, color: provider.color)
    }

    init(title: String, color: BrandColor) {
        self.title = title
        self.color = color
    }

    var body: some View {
        let fill = BrowserSearchProviderFill(brand: color)
        let glows = BrowserSearchProviderGlow.showsBlur(reduceTransparency: reduceTransparency, contrast: contrast)
        Text(verbatim: title)
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(fill.textColor)
            .padding(.horizontal, BrowserCommandPaletteMetrics.providerPillHorizontalPadding)
            .padding(.vertical, BrowserCommandPaletteMetrics.providerPillVerticalPadding)
            .background(fill.fillColor, in: .capsule)
            .shadow(
                color: glows
                    ? color.color.opacity(BrowserCommandPaletteMetrics.providerPillGlowOpacity) : .clear,
                radius: BrowserCommandPaletteMetrics.providerPillGlowRadius)
    }
}
