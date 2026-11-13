import SwiftUI

/// One Space's icon as a picker draws it: the current Space's in its accent,
/// the others quieter, alone in the switcher and on a tile where the Space is
/// picked as an object.
///
/// The shared artwork keeps the icon's colors in both the compact desktop
/// track and the expanded touch segments.
struct BrowserSpacePickerIcon: View {
    let space: BrowserSpaceIdentity
    let metrics: BrowserSpacePickerMetrics
    var isCurrent = true
    var form: BrowserSpaceIconForm = .glyph

    var body: some View {
        BrowserSpaceSymbolArtwork(
            identity: space,
            size: metrics.iconSize,
            lockSize: metrics.lockSize,
            form: form,
            isCurrent: isCurrent
        )
        .padding(metrics.iconPadding)
    }
}
