import SwiftUI

struct BrowserCredentialImportSummaryView: View {
    let review: BrowserCredentialImportReview

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.medium) {
            BrowserCredentialImportReviewSectionHeader(
                title: "Review",
                detail: "Confirm what Ode will change before anything is saved."
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: OdeSpacing.medium) {
                    metrics
                }
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: OdeSpacing.medium
                ) {
                    metrics
                }
            }
        }
    }

    @ViewBuilder
    private var metrics: some View {
        BrowserCredentialImportMetric(
            title: "Ready to import",
            value: review.proposedImportCount,
            systemImage: "checkmark.circle.fill",
            color: OdeColor.success
        )
        BrowserCredentialImportMetric(
            title: "Need review",
            value: review.conflictCount,
            systemImage: "arrow.triangle.branch",
            color: OdeColor.warning
        )
        BrowserCredentialImportMetric(
            title: "Warnings",
            value: review.plan.warnings.count,
            systemImage: "exclamationmark.shield.fill",
            color: OdeColor.warning
        )
        BrowserCredentialImportMetric(
            title: "Rejected rows",
            value: review.plan.rejections.count,
            systemImage: "xmark.octagon.fill",
            color: OdeColor.danger
        )
    }
}
