import SwiftUI

/// Which of a Space's grounds a background paints: the window behind the
/// page, the sidebar a step darker in light and lighter in dark, or the
/// vivid ring around the page, where no text sits.
enum SpaceGroundSurface: Sendable {
    case window
    case sidebar
    case floatingSidebar
    case ring
}

/// A Space's ground: its color at its surface's lightness, turning gently in
/// hue and lightness across the surface, or, for a gradient Space, its
/// colors as soft lights over that ground; with the Space's grain, a fine
/// grain over it. Lightness follows the appearance and moves only away from
/// the text, so text over it keeps its contrast whatever the Space's colors.
struct BrowserSpaceBannerBackground: View {
    let branding: SpaceBranding
    var surface: SpaceGroundSurface = .sidebar

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.browserSpaceGroundReduceTransparency) private var scopedReduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.browserSpaceGroundIncreasedContrast) private var scopedIncreasedContrast
    @Environment(\.appearsActive) private var appearsActive

    private let previewReduceTransparency: Bool?
    private let previewContrast: ColorSchemeContrast?

    init(branding: SpaceBranding, surface: SpaceGroundSurface = .sidebar) {
        self.branding = branding
        self.surface = surface
        previewReduceTransparency = nil
        previewContrast = nil
    }

    init(
        previewBranding branding: SpaceBranding,
        reduceTransparency: Bool,
        contrast: ColorSchemeContrast
    ) {
        self.branding = branding
        previewReduceTransparency = reduceTransparency
        previewContrast = contrast
    }

    var body: some View {
        let inputs = branding.colorInputs
        let roles = SpaceColorRoles(
            inputs, colorScheme: colorScheme, increasedContrast: effectiveContrast == .increased,
            isActive: appearsActive)
        let ring = surface == .ring && SpaceRingColor.showsRing(increasedContrast: effectiveContrast == .increased)
        let ground =
            surface == .sidebar ? roles.sidebar : surface == .floatingSidebar ? roles.floatingSidebar : roles.window
        let colors = branding.groundLightColors
        ZStack {
            if ring {
                BrowserSpaceGroundField(
                    ground: SpaceRingColor.color(inputs, colorScheme: colorScheme, isActive: appearsActive),
                    lights: effectiveReduceTransparency
                        ? [] : SpaceRingColor.lights(inputs, colorScheme: colorScheme, isActive: appearsActive))
            } else {
                BrowserSpaceGroundField(
                    ground: ground,
                    lights: effectiveReduceTransparency
                        ? []
                        : colors.isEmpty
                            ? SpaceGroundLight.derived(over: ground, colorScheme: colorScheme)
                            : colors.map {
                                SpaceGroundLight.color(
                                    $0, over: ground, intensity: inputs.intensity, isActive: appearsActive)
                            }
                )
            }

            // Grain is texture, not depth; a ground asked to be plain, by
            // Reduce Transparency or Increase Contrast, stays smooth.
            if branding.showsTexture, !effectiveReduceTransparency, effectiveContrast != .increased {
                BrowserSpaceGrain(colorScheme: colorScheme)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var effectiveReduceTransparency: Bool {
        previewReduceTransparency ?? scopedReduceTransparency ?? reduceTransparency
    }

    private var effectiveContrast: ColorSchemeContrast {
        previewContrast ?? scopedIncreasedContrast.map { $0 ? .increased : .standard } ?? contrast
    }
}

extension EnvironmentValues {
    /// An explicit contrast input for hosted grounds; nil follows the system.
    @Entry var browserSpaceGroundIncreasedContrast: Bool? = nil

    /// A hosted ground may be asked to draw opaque without changing the
    /// system preference. Otherwise it follows Reduce Transparency.
    @Entry var browserSpaceGroundReduceTransparency: Bool? = nil
}

#if DEBUG
    #Preview("Solid and gradient grounds") {
        HStack(spacing: 16) {
            BrowserSpaceBannerBackground(branding: BrowserSpaceBrandingPreviewFixture.bannerBranding)
            BrowserSpaceBannerBackground(branding: BrowserSpaceBrandingPreviewFixture.gradientBranding)
        }.frame(width: 500, height: 360).padding()
    }
#endif
