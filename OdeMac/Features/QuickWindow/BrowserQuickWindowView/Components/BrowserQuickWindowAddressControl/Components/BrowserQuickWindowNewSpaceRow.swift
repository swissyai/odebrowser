import SwiftUI

/// The picker's last row: keeps the page as a tab of a new Space.
struct BrowserQuickWindowNewSpaceRow: View {
    let add: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.callout.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Text("New Space").lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: BrowserQuickWindowLayout.spacePickerRowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .odeInteractiveSurface(
            isSelected: false,
            isHovering: isHovering,
            cornerRadius: OdeLayout.sidebarControlCornerRadius
        )
        .onHover { isHovering = $0 }
        .accessibilityLabel("Open in New Space")
    }
}
