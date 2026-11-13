import SwiftUI

/// A Space's icon: its one glyph, alone or on a rounded tile, in the Space's
/// own colors. The only way Ode draws a Space's icon, so a Space looks the same
/// in the sidebar, the switcher, menus, Settings and setup.
struct BrowserSpaceIcon: View {
    let symbol: String
    let branding: SpaceBranding
    var form: BrowserSpaceIconForm = .glyph
    var size: CGFloat = 24
    /// Whether this is the Space the window shows or the picker has selected.
    var isCurrent = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.spaceColorRoles) private var ground

    init(
        symbol: String, branding: SpaceBranding, form: BrowserSpaceIconForm = .glyph, size: CGFloat = 24,
        isCurrent: Bool = true
    ) {
        self.symbol = symbol
        self.branding = branding
        self.form = form
        self.size = size
        self.isCurrent = isCurrent
    }

    init(
        identity: BrowserSpaceIdentity, form: BrowserSpaceIconForm = .glyph, size: CGFloat = 24,
        isCurrent: Bool = true
    ) {
        self.init(symbol: identity.symbol, branding: identity.branding, form: form, size: size, isCurrent: isCurrent)
    }

    init(
        space: some BrowserSpaceIdentifying, form: BrowserSpaceIconForm = .glyph, size: CGFloat = 24,
        isCurrent: Bool = true
    ) {
        self.init(identity: space.identity, form: form, size: size, isCurrent: isCurrent)
    }

    var body: some View {
        BrowserSpaceIconDrawing(
            glyph: BrowserSpaceGlyph(symbol: symbol),
            form: form,
            size: size,
            colors: BrowserSpaceIconColors(
                branding: branding, form: form, isCurrent: isCurrent, colorScheme: colorScheme,
                increasedContrast: contrast == .increased, ground: ground)
        )
    }
}

/// A Space's icon drawn with colors already chosen, as the artwork renderer
/// draws it away from any ground.
struct BrowserSpaceIconDrawing: View {
    // MARK: - Static Variables

    /// The tile's corner radius as a fraction of its side.
    static let tileCornerFraction: CGFloat = 0.3
    /// How large the glyph draws on a tile, against the glyph alone, so it
    /// keeps room inside the tile's corners.
    static let tileGlyphScale: CGFloat = 0.85

    // MARK: - Variables

    let glyph: BrowserSpaceGlyph
    let form: BrowserSpaceIconForm
    let size: CGFloat
    let colors: BrowserSpaceIconColors

    var body: some View {
        ZStack {
            if let tile = colors.tile {
                RoundedRectangle(cornerRadius: size * Self.tileCornerFraction, style: .continuous)
                    .fill(tile.color)
            }
            glyphView
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyphView: some View {
        let scale = form == .tile ? Self.tileGlyphScale : 1
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.56 * scale, weight: .semibold))
                .foregroundStyle(colors.glyph.color)
        case .emoji(let emoji):
            Text(verbatim: emoji)
                .font(.system(size: size * 0.68 * scale))
                .opacity(colors.emojiOpacity)
        case .letter(let letter):
            Text(verbatim: letter)
                .font(.system(size: size * 0.62 * scale, weight: .semibold))
                .foregroundStyle(colors.glyph.color)
        }
    }
}

#if DEBUG
    #Preview("Glyph and tile") {
        HStack(spacing: 24) {
            BrowserSpaceIcon(space: BrowserSpaceBrandingPreviewFixture.simpleSpace, size: 32)
            BrowserSpaceIcon(space: BrowserSpaceBrandingPreviewFixture.simpleSpace, size: 32, isCurrent: false)
            BrowserSpaceIcon(space: BrowserSpaceBrandingPreviewFixture.simpleSpace, form: .tile, size: 56)
            BrowserSpaceIcon(
                space: BrowserSpaceBrandingPreviewFixture.simpleSpace, form: .tile, size: 56, isCurrent: false)
        }.padding()
    }
#endif
