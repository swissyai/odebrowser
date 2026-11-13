import SwiftUI

/// Setup uses Ode's ordinary ground until a Space is being edited, then
/// follows that Space live. There is no separate dark stage or timed drift.
struct BrowserOnboardingBackdrop: View {
    // MARK: - Variables

    let branding: SpaceBranding?

    // MARK: - Actions - Presentation

    var body: some View {
        Group {
            if let branding {
                BrowserSpaceBannerBackground(branding: branding, surface: .window)
            } else {
                OdeBrandTheme.canvas
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
