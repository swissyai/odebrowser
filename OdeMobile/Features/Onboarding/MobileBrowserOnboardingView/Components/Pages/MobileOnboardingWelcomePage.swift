import SwiftUI

struct MobileOnboardingWelcomePage: View {
    // MARK: - Variables

    let action: BrowserOnboardingWelcomeAction
    let primaryTitle: String
    let status: String?
    let primaryAction: () -> Void
    let setupWithoutCloudAction: () -> Void

    // MARK: - Actions - Presentation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OdeSpacing.large) {
                BrowserOnboardingWelcomeIllustration()
                    .frame(maxWidth: 224)
                    .frame(maxWidth: .infinity)
                Text("Welcome to Ode")
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(SpaceRoleStyle.secondaryText)
                }
                Button(action: primaryAction) {
                    HStack {
                        if action.waitsOnCloud { ProgressView() }
                        Text(primaryTitle)
                        Image(systemName: "arrow.right")
                    }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: OdeLayout.minimumHitTarget)
                }
                .buttonStyle(.odePrimary)
                .controlSize(.large)
                .disabled(action.waitsOnCloud)
                .accessibilityIdentifier(BrowserMobileAccessibilityID.welcomeContinue)
                if action.offersSetupWithoutCloud {
                    Button(action: setupWithoutCloudAction) {
                        Text("Set Up Without iCloud")
                            .font(.body.weight(.semibold))
                            .frame(minHeight: OdeLayout.minimumHitTarget)
                    }
                    .buttonStyle(.odeSecondary)
                    .controlSize(.large)
                    .accessibilityIdentifier(BrowserMobileAccessibilityID.welcomeSetupWithoutCloud)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(OdeSpacing.extraExtraLarge)
            .frame(maxWidth: .infinity)
        }
        .background(OdeBrandTheme.canvas)
        .foregroundStyle(OdeBrandTheme.textDisplay)
    }
}
