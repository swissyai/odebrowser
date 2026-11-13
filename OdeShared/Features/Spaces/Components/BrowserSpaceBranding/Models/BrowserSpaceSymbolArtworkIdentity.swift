import SwiftUI

/// Everything a drawn Space icon depends on, so the renderer draws each
/// distinct icon once.
struct BrowserSpaceSymbolArtworkIdentity: Equatable, Sendable {
    let glyph: BrowserSpaceGlyph
    let form: BrowserSpaceIconForm
    let colors: BrowserSpaceIconColors
    let requiresAuthentication: Bool
    let size: CGFloat
    let lockSize: CGFloat
    let colorScheme: ColorScheme
    let displayScale: CGFloat
}
