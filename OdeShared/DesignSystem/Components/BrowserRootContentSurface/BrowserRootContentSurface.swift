import SwiftUI

/// The stable root-level frame around browser content. Page states only choose
/// whether their interior is opaque; clipping, the edge and elevation remain
/// owned here. The page meets the window's frame as a crisp rounded edge: a
/// soft shadow onto the frame, a faint hairline to hold a light page or a
/// transparent interior against the frame, and, with Increase Contrast, an
/// edge of at least 3:1 against the frame.
struct BrowserRootContentSurface<Content: View>: View {
    // MARK: - Static Variables

    private static var boundaryStrokeWidth: CGFloat { 0.5 }
    /// The hairline's opacity in each appearance, and with Increase Contrast.
    static var boundaryStrokeOpacity: Double { 0.07 }
    static var increasedContrastStrokeOpacity: Double { 0.5 }

    // MARK: - Variables

    let cornerRadius: CGFloat
    let frameInsets: EdgeInsets
    let usesTransparentInnerSurface: Bool
    let showsFallbackBorder: Bool
    let showsBoundary: Bool
    let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    // MARK: - Initializers

    init(
        cornerRadius: CGFloat,
        frameInsets: EdgeInsets,
        usesTransparentInnerSurface: Bool,
        showsFallbackBorder: Bool = false,
        showsBoundary: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.frameInsets = frameInsets
        self.usesTransparentInnerSurface = usesTransparentInnerSurface
        self.showsFallbackBorder = showsFallbackBorder
        self.showsBoundary = showsBoundary
        self.content = content()
    }

    // MARK: - Actions - Presentation

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        content
            // An engine's page is clipped at its own layer too: its layers,
            // and the remote layer Chromium draws into, don't follow a
            // SwiftUI clip on their own.
            .environment(\.browserWebContentCornerRadius, cornerRadius > 0 ? cornerRadius : nil)
            .background {
                if usesTransparentInnerSurface {
                    Color.clear
                } else {
                    Rectangle().fill(.background)
                }
            }
            // Clip the assembled surface once. Independently clipped backing
            // layers otherwise leave a pale fringe along the upper corners.
            .compositingGroup()
            .clipShape(shape, style: FillStyle(antialiased: true))
            .background {
                OdeLiftedSurfaceShadow(
                    cornerRadius: cornerRadius,
                    opacity: showsBoundary ? OdeLiftedSurfaceShadow.pageShadowOpacity(for: colorScheme) : 0,
                    radius: OdeLiftedSurfaceShadow.pageShadowRadius,
                    yOffset: OdeLiftedSurfaceShadow.pageShadowYOffset
                )
            }
            .overlay {
                shape
                    .strokeBorder(Color.primary.opacity(boundaryOpacity), lineWidth: Self.boundaryStrokeWidth)
                    .allowsHitTesting(false)
            }
            .padding(frameInsets)
    }

    /// How strongly the page's edge is drawn over the frame.
    private var boundaryOpacity: Double {
        guard showsBoundary else { return 0 }
        if contrast == .increased { return Self.increasedContrastStrokeOpacity }
        if showsFallbackBorder { return OdeOpacity.border }
        // A transparent page, such as Start Page, needs an edge even in dark
        // appearance; an opaque engine page keeps its existing fringe-free edge.
        return colorScheme == .dark && !usesTransparentInnerSurface ? 0 : Self.boundaryStrokeOpacity
    }
}
