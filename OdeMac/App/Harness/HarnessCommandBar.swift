#if DEBUG || ODE_REVIEW_BUILD

    import SwiftUI

    /// The Command Bar's card over a given model, for the harness to draw.
    struct HarnessCommandBar: View {
        // MARK: - Variables

        let model: BrowserCommandPaletteModel
        @FocusState private var isFocused: Bool

        // MARK: - Actions - Content

        var body: some View {
            BrowserCommandPaletteCard(
                model: model, presentation: .overlay, maximumResultAreaHeight: 280, morphNamespace: nil,
                restingWidth: nil, queryIsFocused: $isFocused)
        }
    }

#endif
