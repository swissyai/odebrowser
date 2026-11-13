import SwiftUI

/// The query row shares its containing panel's surface.
struct BrowserCommandPaletteSearchField: View {
    // MARK: - Variables

    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let queryIsFocused: FocusState<Bool>.Binding

    @ScaledMetric private var fieldHeight: CGFloat

    // MARK: - Initializers

    init(
        model: BrowserCommandPaletteModel, presentation: BrowserCommandPalettePresentation,
        queryIsFocused: FocusState<Bool>.Binding
    ) {
        self.model = model
        self.presentation = presentation
        self.queryIsFocused = queryIsFocused
        #if os(macOS)
            // The Mac's prominent field reads a step larger.
            if presentation.input == .prominent {
                _fieldHeight = ScaledMetric(wrappedValue: 34, relativeTo: .title)
                return
            }
        #endif
        _fieldHeight = ScaledMetric(
            wrappedValue: presentation.input.fieldHeight, relativeTo: presentation.input.textStyle)
    }

    // MARK: - Actions - Presentation

    var body: some View {
        HStack(spacing: BrowserCommandPaletteMetrics.searchFieldSpacing) {
            if presentation.input.showsSearchGlyph {
                Image(systemName: "magnifyingglass")
                    .font(.system(presentation.input.textStyle, weight: .medium))
                    .foregroundStyle(.paletteDetail)
                    .frame(width: BrowserCommandPaletteMetrics.rowIconContainerSize)
                    .accessibilityHidden(true)
            }

            activeChip

            BrowserPlatformCommandPaletteField(
                model: model,
                presentation: presentation,
                identifier: presentation.fieldIdentifier,
                focused: queryIsFocused.wrappedValue
            )
            .focused(queryIsFocused)
            .frame(height: fieldHeight)

            offer

            if presentation.showsCloseButton {
                Button("Close", systemImage: "xmark", action: model.dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(OdeChromeButtonStyle())
                    .foregroundStyle(.paletteDetail)
            }
        }
        .padding(.horizontal, presentation.input.horizontalPadding)
        .modifier(BrowserCommandPaletteFieldSurface(presentation: presentation))
    }

    /// The search provider the palette is narrowed to, as its solid pill, or
    /// the scope, either of which leaves it when clicked.
    @ViewBuilder
    private var activeChip: some View {
        if let provider = model.activeProvider {
            Button {
                model.leaveScope()
            } label: {
                BrowserSearchProviderPill(provider: provider)
            }
            .buttonStyle(.plain)
            .help("Stop searching \(provider.title)")
            .accessibilityLabel("Stop searching \(provider.title)")
            .accessibilityIdentifier("command-palette-provider-token")
        } else if let scope = model.activeScope {
            Button {
                model.leaveScope()
            } label: {
                if let color = scope.color {
                    BrowserSearchProviderPill(title: String(localized: scope.title), color: color)
                } else {
                    BrowserPaletteScopeChip(scope: scope, showsCloseControl: true, isInteractive: true)
                }
            }
            .buttonStyle(.plain)
            .help("Show all results")
            .accessibilityLabel(Text("Stop searching \(Text(scope.title))"))
            .accessibilityIdentifier("command-palette-scope-token")
        }
    }

    /// What Tab does next, quietly at the field's end: search the site the
    /// text names or completes to, as "Search YouTube" and a Tab keycap, or
    /// enter the scope it names. A completion Tab accepts says nothing here;
    /// on iPhone and iPad, where Tab may be missing, a keycap accepts it.
    @ViewBuilder
    private var offer: some View {
        if let provider = model.providerOffer {
            Button {
                model.enter(provider)
            } label: {
                HStack(spacing: OdeSpacing.small) {
                    Text(verbatim: provider.actionTitle)
                        .font(BrowserCommandPaletteMetrics.rowDetailFont)
                        .foregroundStyle(.paletteDetail)
                        .lineLimit(1)
                    tabKeycap
                }
            }
            .buttonStyle(.plain)
            .help("Press Tab to \(provider.actionTitle)")
            .accessibilityLabel(Text(verbatim: provider.actionTitle))
            .accessibilityHint("Press Tab, enter your query, then press Return.")
            .accessibilityIdentifier("command-palette-provider-offer")
        } else if let scope = model.scopeOffer {
            Button {
                model.enter(scope)
            } label: {
                HStack(spacing: OdeSpacing.small) {
                    // A scope with a pill of its own, as Ode Help has, is
                    // offered the way a site is.
                    if scope.color != nil {
                        Text("Search \(Text(scope.title))")
                            .font(BrowserCommandPaletteMetrics.rowDetailFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        BrowserPaletteScopeChip(scope: scope, isInteractive: true)
                    }
                    tabKeycap
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Search \(Text(scope.title))"))
            .accessibilityIdentifier("command-palette-scope-offer")
        } else {
            #if os(iOS)
                if let completion = model.urlCompletion {
                    Button {
                        model.acceptURLCompletion()
                    } label: {
                        tabKeycap
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accept URL completion")
                    .accessibilityValue(completion.accepted)
                    .accessibilityHint("Fills the address without opening it.")
                    .accessibilityIdentifier("command-palette-accept-completion")
                }
            #endif
        }
    }

    private var tabKeycap: some View {
        BrowserCommandPaletteKeycap {
            #if os(macOS)
                Text("Tab")
            #else
                Image(systemName: "arrow.right.to.line")
            #endif
        }
        .accessibilityHidden(true)
    }
}

/// Insets the query row by one gutter without adding a separate surface.
/// A palette grown out of an address field keeps that field's line instead.
private struct BrowserCommandPaletteFieldSurface: ViewModifier {
    // MARK: - Variables

    let presentation: BrowserCommandPalettePresentation

    // MARK: - Actions - Presentation

    @ViewBuilder
    func body(content: Content) -> some View {
        if presentation.growsFromField {
            content.frame(minHeight: presentation.input.minimumHeight)
        } else {
            content
                .frame(minHeight: presentation.input.minimumHeight - 2 * OdeCornerScale.gutter)
                .padding(OdeCornerScale.gutter)
        }
    }
}

#if DEBUG
    #Preview("Panel query row") {
        @Previewable @FocusState var focused: Bool
        BrowserCommandPaletteSearchField(
            model: BrowserCommandPalettePreviewFixture.model(query: "swift"), presentation: .overlay,
            queryIsFocused: $focused
        )
        .padding().frame(width: 600)
    }
#endif
