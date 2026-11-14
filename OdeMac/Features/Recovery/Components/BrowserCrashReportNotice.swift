import SwiftUI

/// The note each window shows once after a crash, hang or launch that never
/// finished, while the person's choice is to be asked: the report is on this
/// Mac, and the person reviews it, sends it, or leaves it unsent. Two Don't
/// send answers in a row stop it.
struct BrowserCrashReportNotice: View {
    let reports: BrowserCrashReports
    let review: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let asked = reports.unnoticed
        if let newest = asked.first {
            HStack(alignment: .center, spacing: OdeSpacing.medium) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: OdeSpacing.extraExtraSmall) {
                    Text(newest.title)
                        .fontWeight(.semibold)
                    Text(
                        reports.canSend
                            ? "A report is saved on this Mac. Nothing is sent unless you choose to."
                            : "A report is saved on this Mac, and nothing is sent."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: OdeSpacing.medium)
                Button("Don't send") { Task { await reports.answerNotice(about: asked, sends: false) } }
                    .accessibilityIdentifier("report-notice-decline")
                Button("Review") {
                    reports.reviewNotice(about: asked)
                    review()
                }
                .accessibilityIdentifier("report-notice-review")
                if reports.canSend {
                    Button("Send") { Task { await reports.answerNotice(about: asked, sends: true) } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("report-notice-send")
                }
            }
            .font(.callout)
            .padding(.horizontal, OdeSpacing.large)
            .padding(.vertical, OdeSpacing.medium)
            .frame(maxWidth: 640)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: OdeCornerScale.row, style: .continuous).fill(
                        Color(nsColor: .windowBackgroundColor))
                } else {
                    RoundedRectangle(cornerRadius: OdeCornerScale.row, style: .continuous).fill(.regularMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: OdeCornerScale.row, style: .continuous).strokeBorder(
                    .separator, lineWidth: 0.5)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("report-notice")
        }
    }
}
