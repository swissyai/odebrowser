import SwiftUI

/// The core holds the draft; these are only the two transient presentations
/// of it. Finishing remains the host's typed, authorized setup operation.
struct MobileSpaceSetupWizard: View {
    // MARK: - Types

    private enum Step { case appearance, lesson }

    // MARK: - Variables

    let setup: BrowserManualSetupModel
    @Binding var selectedSpaceID: UUID?
    var errorMessage: String?
    let back: () -> Void
    let finish: () -> Void
    @State private var step: Step = .appearance

    private var draft: SetupDraftSpace? { setup.space(selectedSpaceID) }
    private var branding: SpaceBranding { draft?.customization.branding ?? SpaceColorPreset.azure.branding }

    // MARK: - Actions - Presentation

    var body: some View {
        VStack(spacing: 0) {
            if let draft {
                if step == .appearance {
                    Text("Make it yours")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                    BrowserMobileSpaceAppearanceWorkspace(
                        branding: setup.brandingBinding(for: draft.spaceID),
                        symbol: setup.symbolBinding(for: draft.spaceID),
                        name: setup.nameBinding(for: draft.spaceID),
                        spacePicker: spacePicker(for: draft.spaceID), defersDetails: true
                    )
                    .id(draft.spaceID)
                    footer.padding(20)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OdeSpacing.extraExtraLarge) {
                            BrowserOnboardingTabLesson(branding: branding)
                            footer
                        }
                        .frame(maxWidth: 560)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                ContentUnavailableView("Create your first Space", systemImage: "square.grid.2x2")
                Button("Add Space", action: addSpace).buttonStyle(.odePrimary)
                footer.padding(20)
            }
        }
        .background { BrowserSpaceBannerBackground(branding: branding, surface: .window) }
        .spaceColorRoles(for: branding)
        .onAppear { setup.repairSelection($selectedSpaceID) }
        .onChange(of: setup.spaces.map(\.spaceID)) { _, _ in setup.repairSelection($selectedSpaceID) }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.small) {
            if let message = errorMessage ?? setup.errorMessage {
                Text(message).foregroundStyle(SpaceRoleStyle.dangerText).font(.callout)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OdeSpacing.medium) { navigation }
                VStack(alignment: .leading, spacing: OdeSpacing.small) { navigation }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var navigation: some View {
        Button {
            if step == .appearance { back() } else { step = .appearance }
        } label: {
            Label("Back", systemImage: "arrow.left")
                .font(.body.weight(.semibold))
                .frame(minHeight: OdeLayout.minimumHitTarget)
        }
        .buttonStyle(.odeSecondary)
        if step == .appearance {
            Button(action: finish) {
                Text("Open Ode")
                    .font(.body.weight(.semibold))
                    .frame(minHeight: OdeLayout.minimumHitTarget)
            }
            .buttonStyle(.odeSecondary)
            .disabled(draft == nil)
            Button {
                step = .lesson
            } label: {
                Label("Continue", systemImage: "arrow.right")
                    .font(.body.weight(.semibold))
                    .frame(minHeight: OdeLayout.minimumHitTarget)
            }
            .buttonStyle(.odePrimary)
            .disabled(draft == nil)
            .accessibilityIdentifier("space-setup-continue")
        } else {
            Button(action: finish) {
                Label("Open Ode", systemImage: "arrow.right")
                    .font(.body.weight(.semibold))
                    .frame(minHeight: OdeLayout.minimumHitTarget)
            }
            .buttonStyle(.odePrimary)
            .disabled(draft == nil)
            .accessibilityIdentifier("space-setup-continue")
        }
    }

    // MARK: - Actions - Spaces

    private func addSpace() {
        if let added = setup.addSpace() { selectedSpaceID = added }
        step = .appearance
    }

    private func spacePicker(for spaceID: UUID) -> BrowserSpaceCustomizationPicker {
        BrowserSpaceCustomizationPicker(
            spaces: setup.previewSpaces,
            selectedSpaceID: spaceID,
            selectSpace: {
                selectedSpaceID = $0
                setup.errorMessage = nil
                step = .appearance
            },
            moveSpace: { setup.moveSpace($0, to: $1) }, addSpace: addSpace,
            removeSpace: setup.space(spaceID)?.isNew == true
                ? {
                    setup.removeSpace(spaceID)
                    setup.repairSelection($selectedSpaceID)
                } : nil)
    }
}
