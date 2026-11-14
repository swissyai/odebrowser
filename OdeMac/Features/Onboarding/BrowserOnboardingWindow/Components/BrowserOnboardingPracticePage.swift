import SwiftUI

/// Optional examples stay in a disposable browser. Finishing remains available
/// while the examples scroll, without changing the person's unfinished setup.
struct BrowserOnboardingPracticePage: View {
    // MARK: - Variables

    let branding: SpaceBranding
    let back: BrowserOnboardingBackAction
    let finish: () -> Void

    // MARK: - Actions - Presentation

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                BrowserOnboardingTabLesson(branding: branding)
                    .frame(maxWidth: 660)
                    .padding(BrowserOnboardingStageMetrics.inset)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            BrowserOnboardingFooter(back: back) {
                // The focused example keeps native Return/Space activation.
                Button("Open Ode", systemImage: "arrow.right", action: finish)
                    .buttonStyle(.odePrimary)
                    .accessibilityHint("Finishes setup. The examples are optional.")
            }
            .frame(maxWidth: 660)
            .padding(.horizontal, BrowserOnboardingStageMetrics.inset)
            .padding(.bottom, BrowserOnboardingStageMetrics.inset)
        }
    }
}
