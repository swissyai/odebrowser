import SwiftUI

/// The existing setup step hosts a compact real example, not another browser
/// window. The example cannot reconfigure this window or reach personal tabs.
struct BrowserOnboardingPracticePage: View {
    // MARK: - Variables

    let branding: SpaceBranding
    let back: BrowserOnboardingBackAction
    let finish: () -> Void

    // MARK: - Actions - Presentation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OdeSpacing.extraExtraLarge) {
                BrowserOnboardingTabLesson(branding: branding)
                BrowserOnboardingFooter(back: back) {
                    // No global Return shortcut: the focused lesson control
                    // keeps native keyboard activation while this example is open.
                    Button("Open Ode", systemImage: "arrow.right", action: finish)
                        .buttonStyle(.odePrimary)
                        .accessibilityHint("Finishes setup. Trying the example is optional.")
                }
            }
            .frame(maxWidth: 560)
            .padding(BrowserOnboardingStageMetrics.inset)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
