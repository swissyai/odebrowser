import SwiftUI

/// The one way Ode draws a Space's icon as an image: its glyph, alone or on
/// its tile, with the lock of a Space that asks for authentication.
///
/// It draws synchronously, when a view or menu asks, so the icon a menu
/// captures is the Space's own the first time the menu opens, never a stand-in
/// shown while a render is under way. Each look, size, appearance and scale is
/// drawn once and kept, so a changed look is simply a new drawing.
@MainActor
final class BrowserSpaceSymbolArtworkRenderer {
    // MARK: - Static Variables

    static let shared = BrowserSpaceSymbolArtworkRenderer()

    // MARK: - Types

    private struct Drawing {
        let identity: BrowserSpaceSymbolArtworkIdentity
        let image: CGImage
    }

    // MARK: - Variables

    /// The most drawings kept, the least recently used going first: enough for
    /// every Space at each size the switcher, the sidebar and the menus show.
    private let capacity: Int
    private var drawings: [Drawing] = []

    // MARK: - Initializers

    init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    // MARK: - Actions - Drawing

    /// The icon `artwork` describes, drawn at its size, appearance and
    /// scale, or nil in the unlikely case SwiftUI could not draw it.
    func image(for artwork: BrowserSpaceSymbolArtworkIdentity) -> CGImage? {
        if let index = drawings.firstIndex(where: { $0.identity == artwork }) {
            let drawing = drawings.remove(at: index)
            drawings.append(drawing)
            return drawing.image
        }
        let renderer = ImageRenderer(
            content: BrowserSpaceSymbolArtworkContent(
                glyph: artwork.glyph, form: artwork.form, colors: artwork.colors,
                requiresAuthentication: artwork.requiresAuthentication, size: artwork.size,
                lockSize: artwork.lockSize
            )
            .environment(\.colorScheme, artwork.colorScheme))
        renderer.proposedSize = ProposedViewSize(width: artwork.size, height: artwork.size)
        renderer.scale = artwork.displayScale
        guard let image = renderer.cgImage else { return nil }
        if drawings.count == capacity { drawings.removeFirst() }
        drawings.append(Drawing(identity: artwork, image: image))
        return image
    }
}
