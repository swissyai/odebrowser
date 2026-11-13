import SwiftUI

struct BrowserOnboardingPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: OdeRadius.card,
            style: .continuous
        )
        return
            content
            .background(OdeBrandTheme.canvas, in: shape)
            .overlay {
                shape.strokeBorder(
                    OdeBrandTheme.line,
                    lineWidth: OdeLayout.hairline
                )
            }
    }
}
