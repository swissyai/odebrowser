import AppKit
import SwiftUI

extension BrowserSpaceSymbolArtworkRenderer {
    // MARK: - Static Variables

    /// The side of a Space's icon in an AppKit menu, in points.
    static let menuIconSize: CGFloat = 16

    // MARK: - Actions - Menus

    /// The icon an AppKit menu item shows for `space`, such as a Space in the
    /// Dock menu or in a page's context menu: drawn now, in the app's
    /// appearance, for the main screen, or nil in the unlikely case SwiftUI
    /// could not draw it.
    func menuImage(for space: BrowserSpaceIdentity) -> NSImage? {
        let size = Self.menuIconSize
        let colorScheme: ColorScheme =
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        let artwork = BrowserSpaceSymbolArtworkIdentity(
            glyph: BrowserSpaceGlyph(symbol: space.symbol), form: .glyph,
            colors: BrowserSpaceIconColors(
                branding: space.branding, form: .glyph, isCurrent: true, colorScheme: colorScheme),
            requiresAuthentication: space.requiresAuthentication, size: size, lockSize: max(5, size * 0.24),
            colorScheme: colorScheme, displayScale: NSScreen.main?.backingScaleFactor ?? 2)
        guard let image = image(for: artwork) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: size, height: size))
    }
}
