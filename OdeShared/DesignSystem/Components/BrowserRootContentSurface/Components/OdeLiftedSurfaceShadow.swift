import SwiftUI

/// Casts only the exterior part of a rounded surface's shadow.
///
/// The shadow is the shape's own, which Core Animation composites on the GPU.
/// Drawing it into a canvas instead blurred the whole page on the CPU at every
/// step of a window, split or sidebar resize.
struct OdeLiftedSurfaceShadow: View {
    /// A page's shadow onto the frame: soft and close, a few points wide, as
    /// the frame darkens toward the page. A dark frame needs more of it to
    /// show at all.
    static let pageShadowRadius: CGFloat = 6
    static let pageShadowYOffset: CGFloat = 1

    static func pageShadowOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.42 : 0.12
    }
    static let drawingOutset = pageShadowRadius * 2 + abs(pageShadowYOffset)

    let cornerRadius: CGFloat
    let opacity: Double
    let radius: CGFloat
    let yOffset: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if !reduceTransparency, opacity > 0 {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            // Inset, so the cut below covers the casting shape's soft edge.
            shape.inset(by: 1)
                .fill(.black)
                .shadow(color: .black.opacity(opacity), radius: radius, x: 0, y: yOffset)
                // A translucent surface must not show its own shadow through it.
                .mask {
                    Rectangle()
                        .padding(-Self.drawingOutset)
                        .overlay { shape.blendMode(.destinationOut) }
                        .compositingGroup()
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
