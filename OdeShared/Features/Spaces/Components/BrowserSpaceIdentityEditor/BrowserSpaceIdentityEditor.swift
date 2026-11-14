import SwiftUI

/// A Space's appearance as a person edits it: its name, its color from the
/// Space presets, and its icon as an SF symbol, an emoji or a letter.
struct BrowserSpaceIdentityEditor: View {
    // MARK: - Variables

    @Binding var name: String
    @Binding var symbol: String
    @Binding var branding: SpaceBranding
    var defersDetails = false
    @State private var showsDetails = false

    // MARK: - Actions - Presentation

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.extraExtraLarge) {
            nameGroup
            accentGroup
            if defersDetails {
                DisclosureGroup(isExpanded: $showsDetails) {
                    if showsDetails {
                        VStack(alignment: .leading, spacing: OdeSpacing.large) {
                            grainToggle
                            iconGroup
                        }
                        .padding(.top, OdeSpacing.medium)
                    }
                } label: {
                    Text("More options").frame(minHeight: OdeLayout.minimumHitTarget)
                        .odeControlPointer()
                }
            } else {
                grainToggle
                iconGroup
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("space-identity-editor")
    }

    // MARK: - Groups

    private var nameGroup: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.small) {
            Text("Name").font(.headline)
            TextField("Space name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("space-identity-name")
        }
    }

    private var accentGroup: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.small) {
            Text("Color").font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: OdeLayout.minimumHitTarget), spacing: OdeSpacing.small)],
                alignment: .leading, spacing: OdeSpacing.small
            ) {
                ForEach(SpaceColorPreset.all, id: \.self) { preset in
                    BrowserSpaceIdentityColorDot(preset: preset, isSelected: isWorn(preset)) {
                        wear(preset)
                    }
                }
            }
        }
    }

    private var grainToggle: some View {
        Toggle("Grain", isOn: grain)
            .odeControlPointer()
            .help("A fine grain over the Space's color, around the page and behind the sidebar")
            .accessibilityIdentifier("space-identity-grain")
    }

    /// Whether the Space's color wears a fine grain.
    private var grain: Binding<Bool> {
        Binding {
            branding.showsTexture
        } set: { isOn in
            $branding.editorUpdate {
                $0.showsTexture = isOn
                $0.hasCustomAppearance = true
            }
        }
    }

    private var iconGroup: some View {
        let glyph = BrowserSpaceGlyph(symbol: symbol)
        return BrowserIconCustomizationView(
            title: "Icon",
            currentEmoji: glyph.emoji,
            currentSystemSymbol: glyph.systemSymbol,
            currentLetter: glyph.letter,
            suggestionContext: name,
            setEmoji: { wearIcon(BrowserIconSymbol.symbol(forEmoji: $0)) },
            setSystemSymbol: { wearIcon($0) },
            setLetter: { letter in BrowserIconSymbol.symbol(forLetter: letter).map(wearIcon) }
        )
    }

    // MARK: - Choices

    /// Whether the Space wears `preset`: its color is nearer the preset's
    /// swatch than any other's, and close enough to read as it.
    private func isWorn(_ preset: SpaceColorPreset) -> Bool {
        SpaceColorPreset.worn(by: branding) == preset
    }

    private func wear(_ preset: SpaceColorPreset) {
        $branding.editorUpdate {
            $0.colors = ColorPalette(colors: [preset.swatch])
            $0.hasCustomAppearance = true
        }
    }

    /// Gives the Space `symbol` as its icon, in the symbol icon style a Space
    /// stored with an emblem moves to.
    private func wearIcon(_ symbol: String) {
        self.symbol = symbol
        if branding.iconStyle != .simpleSymbol {
            $branding.editorUpdate {
                $0.iconStyle = .simpleSymbol
                $0.hasCustomAppearance = true
            }
        }
    }
}

/// One preset as a round dot in its swatch color, ringed when it is worn.
private struct BrowserSpaceIdentityColorDot: View {
    // MARK: - Variables

    let preset: SpaceColorPreset
    let isSelected: Bool
    let select: () -> Void

    // MARK: - Actions - Presentation

    var body: some View {
        Button(action: select) {
            Circle()
                .fill(preset.swatch.color)
                .frame(width: 24, height: 24)
                .padding(3)
                .overlay {
                    Circle().strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2)
                }
                .frame(width: OdeLayout.minimumHitTarget, height: OdeLayout.minimumHitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(OdeChromeButtonStyle())
        .accessibilityLabel(Text(preset.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("space-identity-color-\(preset.name)")
    }
}
