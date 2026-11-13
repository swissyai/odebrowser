import SwiftUI

/// Geometry shared by selected, pressed, and hovered browser surfaces.
enum OdeInteractiveSurfaceMetrics {
    static let defaultSelectedBorderWidth: CGFloat = 0.5
    static let increasedContrastBorderWidth: CGFloat = 1.5
    static let selectedShadowRadius: CGFloat = 2
    static let selectedShadowYOffset: CGFloat = 1

    /// `width` drawn as a whole number of the display's pixels at `scale`,
    /// never under one: a hairline stays one crisp pixel at 1x and at 2x
    /// instead of a half-covered, blurred one.
    static func snapped(_ width: CGFloat, toPixelsAt scale: CGFloat) -> CGFloat {
        let pixels = max(scale, 1)
        return max(1, (width * pixels).rounded()) / pixels
    }
}

struct OdeInteractiveSurfaceModifier: ViewModifier {
    let isSelected: Bool
    var selectionEmphasis = false
    let isHovering: Bool
    let cornerRadius: CGFloat
    let isPressed: Bool
    let showsRestingSurface: Bool
    let selectedBorderColor: Color
    let selectedBorderWidth: CGFloat
    var customSelectedFill: Color? = nil
    var customHoverFill: Color? = nil
    var customRestingFill: Color? = nil
    var restingBorderColor: Color = .clear
    /// Whether a resting surface is a light, see-through square over the
    /// ground, keeping the Space's color through it, instead of a layer of
    /// the device's material.
    var restsTranslucent = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.spaceColorRoles) private var spaceColorRoles
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
        let isEmphasized = isSelected || isPressed

        content
            .background {
                surface(in: shape)
                    // Keep one hover layer alive in both directions. Inserting
                    // a new fill on entry starts at its final value, while
                    // removing it on exit fades a different render-tree node.
                    .overlay { shape.fill(hoverFill).opacity(isHovering ? 1 : 0) }
                    .overlay { if selectionEmphasis { shape.fill(OdeColor.hover) } }
            }
            .overlay {
                shape
                    .strokeBorder(
                        isEmphasized ? emphasizedBorderColor : restingBorderColor,
                        lineWidth: borderWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(shadowOpacity),
                radius: isEmphasized
                    ? OdeInteractiveSurfaceMetrics.selectedShadowRadius
                    : 0,
                y: isEmphasized
                    ? OdeInteractiveSurfaceMetrics.selectedShadowYOffset
                    : 0
            )
            .animation(accessibleSurfaceAnimation, value: isHovering)
            .animation(accessibleSurfaceAnimation, value: selectionEmphasis)
            // Selection shows at once, as browsers switch tabs; only a press
            // eases in. Fading a selected surface in and out redraws its
            // shadow, its glow and the content it covers every frame, on two
            // surfaces at every tab switch.
            .animation(accessibleSurfaceAnimation, value: isPressed)
    }

    /// Selected, pressed and resting surfaces are layers of the device's
    /// material, wearing their accent tint; hover is only ever a tint, laid
    /// over that material or, on a plain row, alone. On a Space's ground a
    /// selected row is the Space's selected card and a hovered one its hover
    /// color, unless the row asks for its own.
    @ViewBuilder
    private func surface(in shape: RoundedRectangle) -> some View {
        if restsTranslucent, showsRestingSurface, !isSelected, !isPressed {
            shape.fill(Color.white.opacity(Self.translucentRestingOpacity(for: colorScheme)))
                .overlay { if let customRestingFill { shape.fill(customRestingFill) } }
        } else if isSelected || isPressed || showsRestingSurface {
            OdeSurfaceLayer(
                shape: shape,
                tint: isSelected || isPressed ? customSelectedFill ?? roles?.selected.color : customRestingFill
            )
        } else {
            shape.fill(.clear)
        }
    }

    private var hoverFill: Color {
        if let customHoverFill { return customHoverFill }
        return isSelected || isPressed || showsRestingSurface ? OdeColor.hover : roles?.hover.color ?? OdeColor.hover
    }

    /// How much white a translucent resting surface lays over the ground: a
    /// light square on a pale ground, a faint one on a dark ground.
    static func translucentRestingOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.08 : 0.6
    }

    /// The Space roles that apply here, unless the appearance has changed
    /// beneath the Space's ground.
    private var roles: SpaceColorRoles? {
        spaceColorRoles?.applying(in: colorScheme)
    }

    /// The selected row's ring: the Space's separator where the row keeps
    /// the standard ring, so selection never rests on fill color alone.
    private var emphasizedBorderColor: Color {
        guard usesSpaceRing, let roles else { return selectedBorderColor }
        return roles.separator.color
    }

    private var borderWidth: CGFloat {
        let width = usesSpaceRing ? OdeInteractiveSurfaceMetrics.defaultSelectedBorderWidth : selectedBorderWidth
        let shown =
            contrast == .increased ? max(OdeInteractiveSurfaceMetrics.increasedContrastBorderWidth, width) : width
        return OdeInteractiveSurfaceMetrics.snapped(shown, toPixelsAt: displayScale)
    }

    /// Whether the selected ring is the Space's hairline rather than the
    /// row's own.
    private var usesSpaceRing: Bool {
        roles != nil && selectedBorderColor == OdeColor.selectedBorder
    }

    private var shadowOpacity: Double {
        guard isSelected || isPressed, !reduceTransparency else { return 0 }
        return OdeOpacity.interactionSelectionShadow
    }

    private var accessibleSurfaceAnimation: Animation? {
        OdeMotion.surface.unlessReducingMotion(reduceMotion)
    }
}

/// Owns pointer hover state for controls that use Ode's shared interaction
/// surface but do not otherwise need to react to hover themselves.
private struct OdeHoverSurfaceModifier: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat
    let isPressed: Bool
    let showsRestingSurface: Bool
    let selectedBorderColor: Color
    let selectedBorderWidth: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .odeInteractiveSurface(
                isSelected: isSelected,
                isHovering: isHovering && isEnabled,
                cornerRadius: cornerRadius,
                isPressed: isPressed && isEnabled,
                showsRestingSurface: showsRestingSurface,
                selectedBorderColor: selectedBorderColor,
                selectedBorderWidth: selectedBorderWidth
            )
            .onHover { isHovering = $0 }
    }
}

extension View {
    func odeInteractiveSurface(
        isSelected: Bool,
        isHovering: Bool,
        cornerRadius: CGFloat = OdeRadius.compact,
        selectionEmphasis: Bool = false,
        isPressed: Bool = false,
        showsRestingSurface: Bool = false,
        selectedBorderColor: Color = OdeColor.selectedBorder,
        selectedBorderWidth: CGFloat =
            OdeInteractiveSurfaceMetrics.defaultSelectedBorderWidth
    ) -> some View {
        modifier(
            OdeInteractiveSurfaceModifier(
                isSelected: isSelected,
                selectionEmphasis: selectionEmphasis,
                isHovering: isHovering,
                cornerRadius: cornerRadius,
                isPressed: isPressed,
                showsRestingSurface: showsRestingSurface,
                selectedBorderColor: selectedBorderColor,
                selectedBorderWidth: selectedBorderWidth
            )
        )
    }

    func odeHoverSurface(
        isSelected: Bool = false,
        cornerRadius: CGFloat = OdeRadius.compact,
        isPressed: Bool = false,
        showsRestingSurface: Bool = false,
        selectedBorderColor: Color = OdeColor.selectedBorder,
        selectedBorderWidth: CGFloat =
            OdeInteractiveSurfaceMetrics.defaultSelectedBorderWidth
    ) -> some View {
        modifier(
            OdeHoverSurfaceModifier(
                isSelected: isSelected,
                cornerRadius: cornerRadius,
                isPressed: isPressed,
                showsRestingSurface: showsRestingSurface,
                selectedBorderColor: selectedBorderColor,
                selectedBorderWidth: selectedBorderWidth
            )
        )
    }
}
