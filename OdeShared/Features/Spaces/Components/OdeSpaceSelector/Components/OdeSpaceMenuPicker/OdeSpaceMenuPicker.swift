import SwiftUI

/// Picks one Space out of many in a form context.
///
/// A native `Picker` retains the platform menu, keyboard behavior, accessibility
/// role, and selected-value announcement. Ode standardizes the identity row.
struct OdeSpaceMenuPicker<Tag: Hashable>: View {
    let label: LocalizedStringKey
    let spaces: [OdeSpaceIdentity]
    @Binding var selection: Tag
    let tag: (OdeSpaceIdentity) -> Tag
    var labelsHidden = false
    var iconSize: CGFloat = OdeSpaceChipMetrics.menuIconSize
    var accessibilityIdentifier: String?

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(spaces) { identity in
                BrowserSpaceIdentityLabel(
                    identity: identity.space,
                    title: identity.name,
                    iconSize: iconSize
                )
                .tag(tag(identity))
            }
        }
        .modifier(OdeSpaceMenuLabelVisibility(labelsHidden: labelsHidden))
        .accessibilityLabel(Text(label))
        .odeAccessibilityIdentifier(accessibilityIdentifier)
    }
}

#if DEBUG
    #Preview("Select a Space") {
        @Previewable @State var selection: UUID? = SessionState.Seed.preview.spaces[0].id
        OdeSpaceMenuPicker(
            "Default Space", selection: $selection, spaces: OdeSpaceIdentity.list(SpaceModel.previewSpaces)
        )
        .padding().frame(width: 320)
    }
#endif
