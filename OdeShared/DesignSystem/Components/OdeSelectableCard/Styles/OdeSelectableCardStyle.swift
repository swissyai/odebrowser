import SwiftUI

/// Shared selectable surface for callers with custom card content.
struct OdeSelectableCardStyle: ButtonStyle {
    let isSelected: Bool
    var density = OdeSelectableCardDensity.regular
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        OdeSelectableCardSurface(
            isSelected: isSelected,
            density: density,
            tint: tint,
            configuration: configuration
        )
    }
}
