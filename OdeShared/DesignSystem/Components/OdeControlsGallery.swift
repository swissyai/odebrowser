#if DEBUG
    import SwiftUI

    /// Every OdeControls component on one canvas.
    ///
    /// The gallery is the component library's own review surface: a change to a button
    /// role, a field's focus ring, or the selection border shows up here beside every
    /// other control instead of being discovered in whichever pane happened to adopt it.
    /// The previews below cover light, dark, right-to-left, and disabled; selected and
    /// unselected states sit side by side inside the gallery itself.
    ///
    /// Debug-only, and deliberately not wired into any shell.
    struct OdeControlsGallery: View {
        var isEnabled = true

        @State private var placement: TabPlacement = .saved
        @State private var selectedCard = 0
        @State private var chipSelection: UUID? = SessionState.Seed.preview.spaces.first?.id
        @State private var menuSelection: UUID? = SessionState.Seed.preview.spaces.first?.id
        @State private var address = "example.com"
        @State private var name = ""

        private var spaces: [OdeSpaceIdentity] {
            OdeSpaceIdentity.list(SpaceModel.previewSpaces)
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: OdeSpacing.section) {
                    buttons
                    fields
                    segmented
                    cards
                    spacePickers
                    formRows
                }
                .padding(OdeSpacing.extraExtraLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(OdeBrandTheme.canvas)
            .odeFieldSurfaceRole(.brand)
            .disabled(!isEnabled)
        }

        // MARK: - Sections

        private var buttons: some View {
            section("Buttons") {
                HStack(spacing: OdeSpacing.medium) {
                    Button("Save Setup") {}
                        .buttonStyle(.odePrimary)
                    Button("Back") {}
                        .buttonStyle(.odeSecondary)
                    Button("Delete") {}
                        .buttonStyle(.odeDestructive)
                }

                HStack(spacing: OdeSpacing.medium) {
                    Button("Manage Filter Lists") {}
                        .buttonStyle(.odeTertiary)
                    Button {
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.odeIcon())
                    .accessibilityLabel("Add site")
                    Button {
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.odeIcon(isProminent: true))
                    .accessibilityLabel("New Space")
                    Button {
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.odeIcon(tint: OdeBrandPalette.sage))
                    .accessibilityLabel("Remove")
                }

                HStack(spacing: OdeSpacing.medium) {
                    Button("Disabled") {}
                        .buttonStyle(.odePrimary)
                    Button("Disabled") {}
                        .buttonStyle(.odeSecondary)
                    Button {
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.odeIcon(isProminent: true))
                    .accessibilityLabel("Add site")
                }
                .disabled(true)
            }
        }

        private var fields: some View {
            section("Fields") {
                TextField("example.com", text: $address)
                    .odeTextField()
                TextField("Space name", text: $name)
                    .odeTextField()
                TextField("Disabled", text: .constant(""))
                    .odeTextField()
                    .disabled(true)
            }
        }

        private var segmented: some View {
            section("Segmented") {
                Picker("Put new sites in", selection: $placement) {
                    ForEach(TabPlacement.all, id: \.self) { placement in
                        Label(placement.title, systemImage: placement.symbol)
                            .tag(placement)
                    }
                }
                .pickerStyle(.segmented)
                .tint(OdeBrandTheme.accent)

                Picker("Appearance", selection: $placement) {
                    ForEach(TabPlacement.all, id: \.self) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.segmented)
                .tint(OdeBrandTheme.accent)

                Picker("Disabled", selection: .constant(TabPlacement.pinned)) {
                    ForEach(TabPlacement.all, id: \.self) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.segmented)
                .tint(OdeBrandTheme.accent)
                .disabled(true)
            }
        }

        private var cards: some View {
            section("Selectable cards") {
                ForEach(0..<2, id: \.self) { index in
                    OdeSelectableCard(
                        isSelected: selectedCard == index,
                        accessibilityLabel: Text(index == 0 ? "Banner" : "Gradient")
                    ) {
                        selectedCard = index
                    } content: {
                        VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
                            Text(index == 0 ? "Banner" : "Gradient")
                                .font(OdeTypography.displaySection)
                            Text("A patterned band behind the sidebar.")
                                .odeFormFootnote()
                        }
                    }
                }

                OdeSelectableCard(
                    isSelected: true,
                    accessibilityLabel: Text("Disabled"),
                    tint: OdeBrandPalette.sage
                ) {
                } content: {
                    Text("Disabled and selected")
                }
                .disabled(true)

                HStack(spacing: OdeSpacing.small) {
                    ForEach(0..<3, id: \.self) { index in
                        OdeSelectableCard(
                            isSelected: selectedCard == index,
                            accessibilityLabel: Text(verbatim: "Tile \(index + 1)"),
                            density: .compact
                        ) {
                            selectedCard = index
                        } content: {
                            Image(systemName: "seal").font(.title2)
                        }
                    }
                }

                HStack(spacing: OdeSpacing.small) {
                    let colors = [OdeBrandPalette.coral, OdeBrandPalette.butter, OdeBrandPalette.sage]
                    ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                        OdeSelectableCard(
                            isSelected: selectedCard == index,
                            accessibilityLabel: Text(verbatim: "Swatch \(index + 1)"),
                            density: .swatch
                        ) {
                            selectedCard = index
                        } content: {
                            Circle().fill(color).frame(width: 22, height: 22)
                        }
                    }
                }
            }
        }

        private var spacePickers: some View {
            section("Space selection") {
                OdeSpaceChipRail(
                    spaces: spaces,
                    selection: $chipSelection,
                    add: OdeSpaceChipAddAction(title: "New Space") {},
                    commands: { identity in
                        [.remove { _ = identity }]
                    }
                )

                OdeSpaceMenuPicker(
                    "Default Space",
                    selection: $menuSelection,
                    spaces: spaces
                )

                OdeSpaceMenuPicker(
                    "Space",
                    selection: $menuSelection,
                    spaces: spaces,
                    labelsHidden: true
                )
            }
        }

        private var formRows: some View {
            section("Form rows") {
                Form {
                    Section {
                        OdeSettingRow("Default Space") {
                            OdeSpaceMenuPicker(
                                "Default Space",
                                selection: $menuSelection,
                                spaces: spaces,
                                labelsHidden: true
                            )
                        }

                        OdeSettingRow("Reset All") {
                            Button("Reset") {}
                                .buttonStyle(.odeTertiary)
                        }
                    } footer: {
                        OdeFormFootnote(
                            "Startup choices take effect the next time Ode opens a window."
                        )
                    }
                }
                .odeSettingsForm()
                .frame(minHeight: 260)
            }
        }

        // MARK: - Scaffolding

        @ViewBuilder
        private func section<Content: View>(
            _ title: String,
            @ViewBuilder content: () -> Content
        ) -> some View {
            VStack(alignment: .leading, spacing: OdeSpacing.large) {
                Text(verbatim: title)
                    .font(OdeTypography.displayPage)
                    .foregroundStyle(OdeBrandTheme.textDisplay)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
