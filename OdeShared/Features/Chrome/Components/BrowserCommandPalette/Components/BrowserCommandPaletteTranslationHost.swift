import SwiftUI
import Translation

/// Mounted only by an explicit Download Languages action. The typing path
/// uses installed-only sessions and never creates a permission-capable host.
struct BrowserCommandPaletteTranslationHost: ViewModifier {
    // MARK: - Variables

    let model: BrowserCommandPaletteModel

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        let preparation = model.translationPreparation
        content.translationTask(preparation?.configuration) { session in
            guard let preparation else { return }
            await model.prepareTranslation(using: session, preparation: preparation)
        }
    }
}
