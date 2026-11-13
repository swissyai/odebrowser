import SwiftUI

/// A compact welcome with Ode's cast and the next action close at hand.
struct BrowserOnboardingWelcomePage: View {
    // MARK: - Variables

    let action: BrowserOnboardingWelcomeAction
    let hasCompletedSetup: Bool
    let hasDisposableSeedState: Bool
    let cloudUnavailableInBuild: Bool
    let continueSetup: () -> Void
    let setUpWithoutCloud: () -> Void
    let openOde: () -> Void

    private var cloudStatusDetail: String? {
        if hasCompletedSetup || !hasDisposableSeedState { return nil }
        if cloudUnavailableInBuild {
            return String(
                localized: "iCloud sync isn’t available in this build. You can still set up and browse on this Mac.")
        }
        if action.reportsCloudUnavailable {
            return String(localized: "iCloud sync couldn’t be reached. You can set up this Mac without it.")
        }
        return nil
    }

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
            BrowserOnboardingWelcomeIllustration()
                .frame(maxWidth: 320)
            Text("Welcome to Ode")
                .font(OdeTypography.display(40))
                .foregroundStyle(OdeBrandTheme.textDisplay)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            BrowserOnboardingWelcomeCallToAction(
                action: action,
                cloudStatusDetail: cloudStatusDetail,
                perform: performAction,
                setUpWithoutCloud: setUpWithoutCloud
            )
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
