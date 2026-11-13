import SwiftUI

/// A single original-color platform image used anywhere SwiftUI bridges a Space
/// icon into a native control. Without this boundary, menus and pickers can
/// flatten a colored icon into one template symbol or interpret its layers as
/// separate control elements.
///
/// The image is drawn as the view is, never after it: a menu captures its
/// labels once, when it opens, so an icon drawn later would never reach it.
struct BrowserSpaceSymbolArtwork: View {
    // MARK: - Variables

    let identity: BrowserSpaceIdentity
    let size: CGFloat
    let lockSize: CGFloat
    var form: BrowserSpaceIconForm = .glyph
    var isCurrent = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @Environment(\.spaceColorRoles) private var ground

    // MARK: - Initializers

    init(
        space: some BrowserSpaceIdentifying, size: CGFloat, lockSize: CGFloat, form: BrowserSpaceIconForm = .glyph,
        isCurrent: Bool = true
    ) {
        self.init(identity: space.identity, size: size, lockSize: lockSize, form: form, isCurrent: isCurrent)
    }

    init(
        identity: BrowserSpaceIdentity, size: CGFloat, lockSize: CGFloat, form: BrowserSpaceIconForm = .glyph,
        isCurrent: Bool = true
    ) {
        self.identity = identity
        self.size = size
        self.lockSize = lockSize
        self.form = form
        self.isCurrent = isCurrent
    }

    var body: some View {
        let artwork = BrowserSpaceSymbolArtworkIdentity(
            glyph: BrowserSpaceGlyph(symbol: identity.symbol), form: form,
            colors: BrowserSpaceIconColors(
                branding: identity.branding, form: form, isCurrent: isCurrent, colorScheme: colorScheme,
                increasedContrast: contrast == .increased, ground: ground),
            requiresAuthentication: identity.requiresAuthentication, size: size, lockSize: lockSize,
            colorScheme: colorScheme, displayScale: displayScale)
        Group {
            if let image = BrowserSpaceSymbolArtworkRenderer.shared.image(for: artwork) {
                // The renderer already supplies this exact point size. Native
                // picker cells stretch resizable images to their label width.
                Image(decorative: image, scale: displayScale)
                    .renderingMode(.original)
                    .interpolation(.high)
            } else {
                BrowserSpaceSymbolArtworkContent(
                    glyph: artwork.glyph, form: form, colors: artwork.colors,
                    requiresAuthentication: artwork.requiresAuthentication, size: size, lockSize: lockSize)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
