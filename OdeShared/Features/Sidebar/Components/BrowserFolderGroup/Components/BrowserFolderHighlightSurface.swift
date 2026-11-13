import SwiftUI

extension EnvironmentValues {
    @Entry var folderPreviewShowsHighlight = false
    @Entry var folderUsesContrastingForeground = false
    @Entry var folderBackgroundColor: BrandColor? = nil
}

/// A folder's fill: its color's hue and chroma at the sidebar's lightness
/// band, moved along lightness until the Space's text keeps 7:1 and its
/// secondary text 5:1 on it. Strength deepens the chroma rather than the
/// opacity, so a strong folder never lands in the middle tones where neither
/// dark nor light text reads, and the text keeps the Space's roles.
enum BrowserFolderFill {
    static let textFloor = 7.0
    static let secondaryTextFloor = 5.0

    static func color(_ color: BrandColor, strength: Double, roles: SpaceColorRoles) -> OKLCHColor {
        let strength = strength.isFinite ? min(max(strength, 0), 1) : 0
        let source = OKLCHColor(color)
        let dark = roles.colorScheme == .dark
        let start = dark ? 0.26 + 0.04 * strength : 0.90 - 0.04 * strength
        let chroma = source.chroma * (0.35 + 0.65 * strength)
        let text = roles.text.relativeLuminance
        let secondary = roles.secondaryText.relativeLuminance
        func make(_ lightness: Double) -> OKLCHColor {
            OKLCHColor(
                lightness: lightness,
                chroma: min(
                    chroma,
                    SpaceColorRoles.groundClearance * OKLCHColor.maximumChroma(lightness: lightness, hue: source.hue)),
                hue: source.hue)
        }
        func meets(_ fill: OKLCHColor) -> Bool {
            let ground = fill.relativeLuminance
            func ratio(_ other: Double) -> Double { OKLCHColor.contrast(luminance: ground, other) }
            return ratio(text) >= textFloor && ratio(secondary) >= secondaryTextFloor
        }
        // Away from the text: lighter in light, darker in dark.
        var fill = make(start)
        guard !meets(fill) else { return fill }
        var failing = start
        var passing = dark ? 0.02 : 0.995
        for _ in 0..<24 {
            let middle = (failing + passing) / 2
            if meets(make(middle)) { passing = middle } else { failing = middle }
        }
        fill = make(passing)
        return fill
    }
}

/// Shared by live folder groups and the inline settings preview.
struct BrowserFolderHighlightSurface: ViewModifier {
    let color: BrandColor
    let intensity: Double
    var showsFill = true
    var showsBorders = true
    /// How many folders hold this one. Each steps the surface in by the
    /// container padding and rounds it one padding tighter, concentric with
    /// the folder around it.
    var depth = 0
    var isSelected = false
    var emphasisOpacity: Double = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.spaceColorRoles) private var spaceColorRoles
    @Environment(\.folderBackgroundColor) private var parentBackgroundColor

    /// The roles the folder's text draws in: the Space's, or a neutral
    /// Space's where there is none.
    private var roles: SpaceColorRoles {
        spaceColorRoles?.applying(in: colorScheme)
            ?? SpaceColorRoles(.graphite, colorScheme: colorScheme, increasedContrast: contrast == .increased)
    }

    private var fill: OKLCHColor {
        BrowserFolderFill.color(color, strength: intensity, roles: roles)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: depth), style: .continuous)
    }

    func body(content: Content) -> some View {
        let fill = fill
        content
            .background {
                if showsFill {
                    shape.fill(fill.color)
                        .overlay {
                            if emphasisOpacity > 0 { shape.fill(.primary.opacity(emphasisOpacity)) }
                        }
                        .overlay {
                            if isSelected { shape.fill(OdeColor.hover) }
                        }
                        .overlay {
                            if showsBorders {
                                shape.strokeBorder(color.color.opacity(0.5), lineWidth: 1)
                            }
                        }
                        .padding(.leading, BrowserFolderLayout.surfaceLeadingInset(depth: depth))
                        .padding(.trailing, BrowserSidebarMetrics.layerInset)
                        .allowsHitTesting(false)
                }
            }
            .environment(\.folderUsesContrastingForeground, showsFill)
            .environment(\.folderBackgroundColor, showsFill ? fill.brandColor : parentBackgroundColor)
    }
}
