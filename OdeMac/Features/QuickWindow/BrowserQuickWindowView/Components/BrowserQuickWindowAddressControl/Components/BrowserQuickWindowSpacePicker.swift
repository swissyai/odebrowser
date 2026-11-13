import SwiftUI

/// The Spaces a Quick Window may browse instead, chosen from its Space chip.
struct BrowserQuickWindowSpacePicker: View {
    // MARK: - Variables

    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let selectSpace: (BrowserSpaceIdentity) -> Void
    /// Keeps the page in a Space added for it; nil where the window may not.
    var addSpace: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(spaces) { space in
                BrowserQuickWindowSpacePickerRow(
                    space: space,
                    isSelected: space.id == selectedSpaceID,
                    select: { selectSpace(space) }
                )
            }
            if let addSpace {
                Divider()
                    .padding(.vertical, 2)
                BrowserQuickWindowNewSpaceRow(add: addSpace)
            }
        }
        .padding(6)
        .frame(width: BrowserQuickWindowLayout.spacePickerWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose Quick Window Space")
    }
}
