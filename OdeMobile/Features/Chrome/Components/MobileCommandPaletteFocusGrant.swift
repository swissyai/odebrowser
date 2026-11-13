import SwiftUI

/// Whether a Command Bar field may put the keyboard up when it appears, which
/// the window answers through `browserCommandPaletteFocusesOnAppear`.
///
/// On a touch screen, a Start Page appearing is not a reason to type: a
/// software keyboard would cover half the window each time one shows, on
/// iPad and on iPhone Duo's inner display alike. The Start Page's field takes
/// focus only for a request the person made, such as New Tab or Open
/// Location, and only once for each. The overlay Command Bar opens only on
/// request, so it always takes focus.
///
/// A connected hardware keyboard is no exception: the Simulator reports one
/// while it shows the software keyboard, and ⌘T and ⌘L are requests anyway.
@MainActor
final class MobileCommandPaletteFocusGrant {
    // MARK: - Variables

    /// Whether the person asked for the Start Page's field and it has not
    /// taken focus since.
    private(set) var hasPendingRequest = false

    // MARK: - Actions - Granting

    /// The person asked for the Start Page's field.
    func grant() {
        hasPendingRequest = true
    }

    /// Whether a field of `presentation` that just appeared takes focus,
    /// using up the pending request when it is the one that allows it.
    func takesFocus(presentation: BrowserCommandPalettePresentation) -> Bool {
        guard presentation == .embedded else { return true }
        guard hasPendingRequest else { return false }
        hasPendingRequest = false
        return true
    }
}
