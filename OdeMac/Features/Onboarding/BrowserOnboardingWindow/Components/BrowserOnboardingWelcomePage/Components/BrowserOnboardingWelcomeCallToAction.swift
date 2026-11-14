import SwiftUI

struct BrowserOnboardingWelcomeCallToAction: View {
    // MARK: - Variables

    let action: BrowserOnboardingWelcomeAction
    let cloudStatusDetail: String?
    let perform: () -> Void
    let setUpWithoutCloud: () -> Void

    // MARK: - Actions - Presentation

    var body: some View {
        VStack(spacing: 12) {
            Button(action: perform) {
                HStack(spacing: 10) {
                    if action.waitsOnCloud {
                        ProgressView().controlSize(.small)
                    }
                    Text(action.opensOde ? "Open Ode" : "Continue")
                    Image(systemName: "arrow.right")
                }
                .frame(minWidth: 120)
            }
            .buttonStyle(.odePrimary)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(action.waitsOnCloud)
            .accessibilityLabel(
                action.opensOde ? Text("Open Ode") : Text("Continue")
            )
            .accessibilityIdentifier("onboarding-welcome-continue")

            if let status = action.waitsOnCloud
                ? String(localized: "Checking iCloud for an existing setup…") : cloudStatusDetail
            {
                Text(status)
                    .font(OdeTypography.sans(12, weight: .medium))
                    .foregroundStyle(OdeBrandTheme.textSecondary)
            }

            if action.offersSetupWithoutCloud {
                Button("Set Up Without iCloud", action: setUpWithoutCloud)
                    .buttonStyle(.odeTertiary)
                    .accessibilityIdentifier("onboarding-welcome-setup-without-icloud")
            }
        }
        .multilineTextAlignment(.center)
    }
}
