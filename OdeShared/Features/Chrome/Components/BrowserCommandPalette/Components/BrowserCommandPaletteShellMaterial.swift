import SwiftUI

/// The palette's surface: its own color at nearly full strength over a strong
/// blur of the page beneath, so it reads as solid, with only a trace of the
/// page's color, and is never see-through; raised over the page by a hairline
/// and a soft shadow. Reduce Transparency draws the color solid.
struct BrowserCommandPaletteShellMaterial: ViewModifier {
    let shape: RoundedRectangle

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        let surface = dark ? BrowserCommandPaletteMetrics.darkSurface : BrowserCommandPaletteMetrics.lightSurface
        content
            .background(
                surface.opacity(reduceTransparency ? 1 : BrowserCommandPaletteMetrics.surfaceOpacity), in: shape
            )
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(dark ? 0.2 : 0.04), radius: 2, y: 2)
            .shadow(color: .black.opacity(dark ? 0.35 : 0.09), radius: 18, y: 14)
    }
}
