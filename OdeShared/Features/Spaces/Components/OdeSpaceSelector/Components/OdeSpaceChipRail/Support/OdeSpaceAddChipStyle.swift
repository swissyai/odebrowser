import SwiftUI

/// The dashed "one more" chip.
struct OdeSpaceAddChipStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        OdeSpaceAddChipSurface(
            tint: tint,
            isPressed: configuration.isPressed,
            label: configuration.label
        )
        .odeControlPointer()
    }
}
