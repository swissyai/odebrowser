import SwiftUI

/// A compact welcome with Ode's cast and the next action close at hand.
struct BrowserOnboardingWelcomePage: View {
    // MARK: - Variables

    let action: BrowserOnboardingWelcomeAction
    let continueSetup: () -> Void
    let setUpWithoutCloud: () -> Void
    let openOde: () -> Void

    // MARK: - Actions - Presentation

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                column
                    .frame(maxWidth: 440)
                    .padding(BrowserOnboardingStageMetrics.inset)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
            }
        }
    }

    private var column: some View {
        VStack(spacing: OdeSpacing.extraExtraLarge) {
            Text("Welcome to Ode")
                .font(OdeTypography.display(40))
                .foregroundStyle(OdeBrandTheme.textDisplay)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            BrowserOnboardingWelcomeCallToAction(
                action: action,
                perform: performAction,
                setUpWithoutCloud: setUpWithoutCloud
            )
            BrowserOnboardingWelcomeIllustration()
                .frame(maxWidth: 320)
        }
    }

    // MARK: - Actions - Navigation

    private func performAction() {
        guard !action.waitsOnCloud else { return }
        if action.opensOde {
            openOde()
        } else {
            continueSetup()
        }
    }
}
