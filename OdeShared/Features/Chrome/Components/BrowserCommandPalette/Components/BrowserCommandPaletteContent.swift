import SwiftUI

#if os(macOS)
    typealias BrowserCommandPaletteFocusBinding = Binding<Bool>
#else
    typealias BrowserCommandPaletteFocusBinding = FocusState<Bool>.Binding
#endif

struct BrowserCommandPaletteContent: View {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let morphNamespace: Namespace.ID?
    let overlayContentLeadingInset: CGFloat
    var overlayContentInsets: EdgeInsets? = nil
    var fieldFrame: CGRect? = nil
    var restoresQueryFocus = false

    #if os(macOS)
        // AppKit owns native focus and selection. This state is only an intent;
        // a second SwiftUI focus owner would reselect text already entered.
        @State private var queryIsFocused = false
    #else
        @FocusState private var queryIsFocused: Bool
    #endif
    @Environment(\.spaceContentIsInteractive) private var spaceContentIsInteractive
    @Environment(\.browserCommandPaletteFocusesOnAppear) private var focusesOnAppear
    @Environment(\.isEnabled) private var isEnabled

    private var canFocus: Bool { isEnabled && spaceContentIsInteractive }

    var body: some View {
        BrowserCommandPalettePresentationView(
            model: model,
            presentation: presentation,
            morphNamespace: morphNamespace,
            overlayContentLeadingInset: overlayContentLeadingInset,
            overlayContentInsets: overlayContentInsets,
            fieldFrame: fieldFrame,
            queryIsFocused: $queryIsFocused
        )
        .task(id: canFocus) {
            guard canFocus else {
                queryIsFocused = false
                return
            }
            await Task.yield()
            guard !Task.isCancelled, canFocus, restoresQueryFocus || focusesOnAppear(presentation) else { return }
            queryIsFocused = true
        }
        .onKeyPress(.downArrow) {
            guard !model.completionEditing.isComposing else { return .ignored }
            model.moveSelection(by: presentation.listsUpward ? -1 : 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !model.completionEditing.isComposing else { return .ignored }
            model.moveSelection(by: presentation.listsUpward ? 1 : -1)
            return .handled
        }
        .browserPaletteExitCommand(
            presentation.closesOnExit ? model.dismiss : {}
        )
    }
}

/// Whether a palette of a presentation focuses its field as it appears.
typealias BrowserCommandPaletteAppearanceFocus = @MainActor @Sendable (BrowserCommandPalettePresentation) -> Bool

extension EnvironmentValues {
    /// Every palette focuses its field as it appears, unless the platform says
    /// otherwise: a touch screen's keyboard covers half the window, so iOS
    /// keeps it down for a Start Page that appears by itself.
    @Entry var browserCommandPaletteFocusesOnAppear: BrowserCommandPaletteAppearanceFocus = { _ in true }
}
