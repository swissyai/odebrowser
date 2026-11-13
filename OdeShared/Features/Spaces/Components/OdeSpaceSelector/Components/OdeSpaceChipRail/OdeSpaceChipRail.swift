import SwiftUI

/// A horizontal rail of Space chips, each with its icon, ending in a dashed add chip.
/// The chips stand in a row where they fit the width they are offered, and
/// scroll sideways where there are more than fit.
struct OdeSpaceChipRail: View {
    let spaces: [OdeSpaceIdentity]
    @Binding var selection: UUID?
    var add: OdeSpaceChipAddAction?
    var commands: ((OdeSpaceIdentity) -> [OdeSpaceChipCommand])?
    var accessibilityIdentifier: String?

    init(
        spaces: [OdeSpaceIdentity],
        selection: Binding<UUID?>,
        add: OdeSpaceChipAddAction? = nil,
        commands: ((OdeSpaceIdentity) -> [OdeSpaceChipCommand])? = nil,
        accessibilityIdentifier: String? = nil
    ) {
        self.spaces = spaces
        _selection = selection
        self.add = add
        self.commands = commands
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips
            ScrollView(.horizontal) { chips }
                .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .odeAccessibilityIdentifier(accessibilityIdentifier)
    }

    private var chips: some View {
        HStack(spacing: OdeSpaceChipMetrics.railSpacing) {
            ForEach(spaces) { identity in
                chip(identity)
            }

            if let add {
                addChip(add)
            }
        }
        .padding(.vertical, OdeSpacing.extraExtraSmall)
        .odeCollectionMotion(ids: spaces.map(\.id))
    }

    private func chip(_ identity: OdeSpaceIdentity) -> some View {
        let isSelected = identity.id == selection
        return Button {
            selection = identity.id
        } label: {
            HStack(spacing: OdeSpaceChipMetrics.contentSpacing) {
                BrowserSpaceSymbolArtwork(
                    identity: identity.space,
                    size: OdeSpaceChipMetrics.iconSize,
                    lockSize: OdeSpaceChipMetrics.lockSize,
                    isCurrent: isSelected
                )
                Text(verbatim: identity.name)
                    .lineLimit(1)
            }
        }
        .buttonStyle(
            OdeSpaceChipStyle(tint: identity.tint, isSelected: isSelected)
        )
        .accessibilityLabel(Text(verbatim: identity.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .odeCollectionItemTransition()
        .modifier(OdeSpaceChipCommands(commands: commands?(identity) ?? []))
    }

    private func addChip(_ add: OdeSpaceChipAddAction) -> some View {
        Button(action: add.perform) {
            HStack(spacing: OdeSpaceChipMetrics.contentSpacing) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                Text(add.title)
                    .lineLimit(1)
            }
        }
        .buttonStyle(OdeSpaceAddChipStyle(tint: addTint))
        .accessibilityLabel(Text(add.title))
        .odeAccessibilityIdentifier(add.accessibilityIdentifier)
    }

    private var addTint: Color {
        spaces.first { $0.id == selection }?.tint ?? OdeBrandTheme.accent
    }
}

#if DEBUG
    #Preview("Select a Space") {
        @Previewable @State var selection: UUID? = SessionState.Seed.preview.spaces[0].id
        OdeSpaceChipRail(spaces: OdeSpaceIdentity.list(SpaceModel.previewSpaces), selection: $selection)
            .padding().frame(width: 360)
    }
#endif
