import SwiftUI

/// Section choices use the same selected, hover and pressed surface as sidebar rows.
struct BrowserUtilityNavigationButtonStyle: ButtonStyle {
    // MARK: - Variables

    let isSelected: Bool

    // MARK: - Actions - Surface

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .odeHoverSurface(
                isSelected: isSelected,
                cornerRadius: BrowserSidebarMetrics.layerCornerRadius(),
                isPressed: configuration.isPressed
            )
    }
}
