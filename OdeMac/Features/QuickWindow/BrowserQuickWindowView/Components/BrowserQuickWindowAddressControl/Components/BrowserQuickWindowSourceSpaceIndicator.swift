import SwiftUI

/// The Space the Quick Window browses, shown by its emblem, which opens the
/// Spaces it may switch to: choosing one reopens the page with that Space's
/// website data and passwords.
struct BrowserQuickWindowSourceSpaceIndicator: View {
    let space: BrowserSpaceIdentity?
    let spaces: [BrowserSpaceIdentity]
    let selectSpace: (BrowserSpaceRuntimeAssignment) -> Void
    /// Keeps the page as a tab of a Space added for it, where the window may.
    var addSpace: (() -> Void)?

    @State private var isPickerPresented = false

    var body: some View {
        Button {
            isPickerPresented.toggle()
        } label: {
            Group {
                if let space {
                    BrowserSpaceSymbolArtwork(space: space, size: 20, lockSize: 5)
                } else {
                    Image(systemName: "square.grid.2x2")
                }
            }
            .font(.callout.weight(.semibold))
            .frame(width: OdeLayout.minimumHitTarget, height: OdeLayout.minimumHitTarget)
            .background(
                OdeColor.hover,
                in: .rect(cornerRadius: OdeRadius.compact, style: .continuous)
            )
        }
        .buttonStyle(
            OdeChromeButtonStyle(controlSize: nil, cornerRadius: OdeRadius.compact)
        )
        .disabled(space == nil)
        .fixedSize()
        .help(space?.name ?? String(localized: "Space"))
        .accessibilityLabel("Current Quick Window Space")
        .accessibilityValue(space?.name ?? "Space")
        .accessibilityIdentifier("quick-window-source-space")
        .odePopover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            if let space {
                BrowserQuickWindowSpacePicker(
                    spaces: spaces,
                    selectedSpaceID: space.id,
                    selectSpace: { candidate in
                        isPickerPresented = false
                        selectSpace(candidate.assignment)
                    },
                    addSpace: addSpace.map { addSpace in
                        {
                            isPickerPresented = false
                            addSpace()
                        }
                    }
                )
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        let spaces = SpaceModel.previewSpaces.map(\.identity)
        BrowserQuickWindowSourceSpaceIndicator(space: spaces[0], spaces: spaces, selectSpace: { _ in })
            .padding()
    }
#endif
