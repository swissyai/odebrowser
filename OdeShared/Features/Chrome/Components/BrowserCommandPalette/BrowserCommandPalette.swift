import SwiftUI

/// Ode's shared launcher, presented as an overlay, on the Start Page, or
/// grown out of an address field.
@MainActor
struct BrowserCommandPalette: View {
    let presentation: BrowserCommandPalettePresentation
    /// The window's command-surface namespace, in which an overlay palette
    /// grows out of its Space's address field. Absent where the palette
    /// appears in place.
    let morphNamespace: Namespace.ID?
    let overlayContentLeadingInset: CGFloat
    let overlayContentInsets: EdgeInsets?
    /// The frame of the address field a palette grows out of, in the space
    /// the palette is laid out in.
    let fieldFrame: CGRect?

    /// Holds the model once it is made. SwiftUI makes this view again each
    /// time its parent updates while the palette is open; only the first
    /// one's model is kept, so the model is made on first use, not in `init`.
    @State private var storage = Storage()
    private let makeModel: () -> BrowserCommandPaletteModel
    private let query: Binding<String>?
    private let focus: Binding<Bool>?

    init(
        browser: BrowserStore,
        space: SpaceModel?,
        selectedTabID: UUID?,
        initialQuery: String = "",
        query: Binding<String>? = nil,
        focus: Binding<Bool>? = nil,
        commands: @autoclosure @escaping () -> BrowserCommandPaletteCommandRegistry? = nil,
        offersRestingCommands: Bool = true,
        isSourceAvailable: @escaping (BrowserTabRuntimeAssignment) -> Bool,
        selectTab:
            @escaping (
                BrowserTabRuntimeAssignment,
                BrowserTabRuntimeAssignment
            ) -> Bool,
        openURL: @escaping (BrowserTabRuntimeAssignment, URL, BrowserCommandPaletteOpening) -> Bool,
        dismiss: @escaping () -> Void,
        presentation: BrowserCommandPalettePresentation = .overlay,
        morphNamespace: Namespace.ID? = nil,
        overlayContentLeadingInset: CGFloat = 0,
        overlayContentInsets: EdgeInsets? = nil,
        fieldFrame: CGRect? = nil,
        destination: (any BrowserPaletteDestination)? = nil,
        openings: [BrowserCommandPaletteOpening] = [.here],
        readPasteboard: @escaping () -> String? = { nil }
    ) {
        self.presentation = presentation
        self.query = query
        self.focus = focus
        self.morphNamespace = morphNamespace
        self.overlayContentLeadingInset = overlayContentLeadingInset
        self.overlayContentInsets = overlayContentInsets
        self.fieldFrame = fieldFrame
        makeModel = {
            let model = BrowserCommandPaletteModel(
                browser: browser,
                space: space,
                selectedTabID: selectedTabID,
                initialQuery: query?.wrappedValue ?? initialQuery,
                commands: commands(),
                offersRestingCommands: offersRestingCommands,
                presentation: presentation,
                lookups: BrowserCommandPaletteLookups(readPasteboard: readPasteboard),
                isSourceAvailable: isSourceAvailable,
                selectTab: selectTab,
                openURL: openURL,
                dismiss: dismiss,
                destination: destination,
                openings: openings
            )
            model.focusChanged = { focus?.wrappedValue = $0 }
            return model
        }
    }

    private var model: BrowserCommandPaletteModel {
        if let model = storage.model { return model }
        let model = makeModel()
        storage.model = model
        return model
    }

    var body: some View {
        let model = model
        BrowserCommandPaletteContent(
            model: model,
            presentation: presentation,
            morphNamespace: morphNamespace,
            overlayContentLeadingInset: overlayContentLeadingInset,
            overlayContentInsets: overlayContentInsets,
            fieldFrame: fieldFrame,
            restoresQueryFocus: focus?.wrappedValue == true
        )
        .modifier(BrowserCommandPaletteTranslationHost(model: model))
        .onChange(of: model.query) { _, value in
            query?.wrappedValue = value
        }
        .onChange(of: model.isCompletionSourceAvailable) { _, available in
            model.sourceAvailabilityChanged(available)
        }
        .onChange(of: model.preferences) { model.preferencesChanged() }
        .onDisappear { model.stop() }
    }

    @MainActor
    private final class Storage {
        var model: BrowserCommandPaletteModel?
    }
}

#Preview("Command Palette — Overlay") {
    ZStack {
        OdeBrandTheme.canvas
        BrowserCommandPalette(
            browser: BrowserCommandPalettePreviewFixture.browser,
            space: BrowserCommandPalettePreviewFixture.space,
            selectedTabID: BrowserCommandPalettePreviewFixture.selectedTabID,
            initialQuery: "swift",
            commands: BrowserCommandPalettePreviewFixture.registry,
            isSourceAvailable: { _ in true },
            selectTab: { _, _ in true },
            openURL: { _, _, _ in true },
            dismiss: {}
        )
    }
    .frame(width: 980, height: 720)
}

#Preview("Command Palette — Embedded") {
    BrowserCommandPalette(
        browser: BrowserCommandPalettePreviewFixture.browser,
        space: BrowserCommandPalettePreviewFixture.space,
        selectedTabID: BrowserCommandPalettePreviewFixture.selectedTabID,
        commands: BrowserCommandPalettePreviewFixture.registry,
        offersRestingCommands: false,
        isSourceAvailable: { _ in true },
        selectTab: { _, _ in true },
        openURL: { _, _, _ in true },
        dismiss: {},
        presentation: .embedded
    )
    .padding(OdeSpacing.large)
    .frame(width: 760)
}
