import SwiftUI

/// An opaque surface for recovery suggestions and technical details.
private struct BrowserNavigationFailureCard: ViewModifier {
    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: OdeCornerScale.surface, style: .continuous)
            shape.fill(OdeBrandTheme.surface)
            shape.strokeBorder(OdeBrandTheme.line, lineWidth: OdeLayout.hairline)
        }
    }
}

extension View {
    func browserNavigationFailureCard() -> some View {
        modifier(BrowserNavigationFailureCard())
    }
}
