import SwiftUI

/// A Space chip, lit in the Space's own color while it is the one chosen.
struct OdeSpaceChipStyle: ButtonStyle {
    let tint: Color
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        OdeSpaceChipSurface(
            tint: tint,
            isSelected: isSelected,
            isPressed: configuration.isPressed,
            label: configuration.label
        )
        .odeControlPointer()
    }
}
