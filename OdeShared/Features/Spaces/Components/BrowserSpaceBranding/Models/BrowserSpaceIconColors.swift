import SwiftUI

/// How a Space's icon is drawn: the glyph alone, where the sidebar's chrome
/// stays quiet, or on a rounded tile, where a Space stands alone as an object.
enum BrowserSpaceIconForm: Hashable, Sendable {
    case glyph
    case tile
}

/// The colors a Space's icon draws with, all from the Space's own roles. The
/// current Space's glyph or tile takes its accent; any other glyph takes the
/// secondary text of the ground it sits on, and any other tile the Space's
/// hover tint.
struct BrowserSpaceIconColors: Equatable, Sendable {
    // MARK: - Static Variables

    /// How opaque an emoji draws as another Space's glyph, so the current
    /// Space's stands out the way a colored glyph does.
    static let quietEmojiOpacity = 0.6

    // MARK: - Variables

    /// The glyph's color; an emoji keeps its own colors.
    let glyph: BrandColor
    /// The tile behind the glyph, in the tile form.
    let tile: BrandColor?
    let emojiOpacity: Double

    // MARK: - Initializers

    /// The colors for a Space wearing `branding`, drawn as `form` in
    /// `colorScheme`. `ground` is the roles of the Space whose ground the icon
    /// sits on, when it sits on one.
    init(
        branding: SpaceBranding,
        form: BrowserSpaceIconForm,
        isCurrent: Bool,
        colorScheme: ColorScheme,
        increasedContrast: Bool = false,
        ground: SpaceColorRoles? = nil
    ) {
        let own = SpaceColorRoles(branding.colorInputs, colorScheme: colorScheme, increasedContrast: increasedContrast)
        switch form {
        case .glyph:
            let quiet = ground?.applying(in: colorScheme) ?? own
            glyph = isCurrent ? own.accentSolid.brandColor : quiet.secondaryText.brandColor
            tile = nil
            emojiOpacity = isCurrent ? 1 : Self.quietEmojiOpacity
        case .tile:
            glyph = isCurrent ? own.labelOnSolid.brandColor : own.secondaryText.brandColor
            tile = isCurrent ? own.accentSolid.brandColor : own.hover.brandColor
            emojiOpacity = 1
        }
    }
}
