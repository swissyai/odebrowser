import SwiftUI

/// Appearance only; selection, promotion and drag owners remain on the row.
struct BrowserTabAppearanceSurface: ViewModifier {
    let appearance: BrowserTabAppearance
    let accent: Color
    let isPinned: Bool
    let isSelected: Bool
    let isHovering: Bool
    var selectionEmphasis = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.sidebarLayerDepth) private var depth

    func body(content: Content) -> some View {
        let radius = BrowserSidebarMetrics.layerCornerRadius(depth: depth)
        let selectedAccent = isPinned || appearance.outlinesSelectedTabs
        let showsBorder = appearance.borders == .all || (isPinned && appearance.borders == .pinned)
        // Each choice is read only where it shows, so a drag of the pin fill
        // or the hover tint re-renders the pins or the hovered row alone.
        let fill = isPinned ? BrowserTabAppearance.intensity(appearance.pinFill) : 0
        let hover = isHovering ? BrowserTabAppearance.intensity(appearance.hoverFill) : 0
        content
            .modifier(
                OdeInteractiveSurfaceModifier(
                    isSelected: isSelected, selectionEmphasis: selectionEmphasis,
                    isHovering: isHovering, cornerRadius: radius, isPressed: false,
                    showsRestingSurface: isPinned,
                    selectedBorderColor: selectedAccent ? accent : OdeColor.selectedBorder,
                    selectedBorderWidth: isPinned ? OdeLayout.pinnedAccentBorderWidth : 1,
                    customSelectedFill: isPinned && fill > 0 && !reduceTransparency ? accent.opacity(fill * 0.5) : nil,
                    // Hover keeps its standard weight; the setting only decides how much of
                    // the accent is in it, from the neutral hover to the accent itself.
                    customHoverFill: hover > 0 && !reduceTransparency
                        ? Color.primary.mix(with: accent, by: hover).opacity(OdeOpacity.hover) : nil,
                    customRestingFill: isPinned && fill > 0 && !reduceTransparency ? accent.opacity(fill * 0.2) : nil,
                    restingBorderColor: showsBorder ? accent : .clear,
                    // A pinned tile rests as a see-through square on the
                    // Space's color, as favorites do.
                    restsTranslucent: isPinned)
            )
            .background {
                if isSelected, appearance.pinGlow > 0, !reduceTransparency {
                    BrowserTabSelectionGlow(
                        cornerRadius: radius,
                        color: accent.opacity(BrowserTabAppearance.intensity(appearance.pinGlow) * 0.6)
                    )
                }
            }
    }
}
