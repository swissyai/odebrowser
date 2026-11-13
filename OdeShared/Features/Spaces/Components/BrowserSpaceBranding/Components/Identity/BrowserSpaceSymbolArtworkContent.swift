import SwiftUI

/// A Space's icon with the lock of a Space that asks for authentication, in
/// colors already chosen.
struct BrowserSpaceSymbolArtworkContent: View {
    let glyph: BrowserSpaceGlyph
    let form: BrowserSpaceIconForm
    let colors: BrowserSpaceIconColors
    let requiresAuthentication: Bool
    let size: CGFloat
    let lockSize: CGFloat

    var body: some View {
        BrowserSpaceIconDrawing(glyph: glyph, form: form, size: size, colors: colors)
            .overlay(alignment: .bottomTrailing) {
                if requiresAuthentication {
                    Image(systemName: "lock.fill")
                        .font(.system(size: lockSize, weight: .bold))
                        .padding(2)
                        .background(.background, in: .circle)
                }
            }
            .frame(width: size, height: size)
    }
}
