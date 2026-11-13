import SwiftUI

struct BrowserNavigationFailureTechnicalDetails: View {
    let failure: PageFailure

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.medium) {
            Text("Technical details")
                .font(.headline)

            BrowserNavigationFailureDetailRow(label: "Code", value: failure.error.code)

            if let failingURL = failure.failingURL {
                BrowserNavigationFailureDetailRow(
                    label: "Address",
                    value: failingURL.absoluteString
                )
            }
            BrowserNavigationFailureDetailRow(
                label: "Error domain",
                value: failure.domain
            )
            BrowserNavigationFailureDetailRow(
                label: "Error number",
                value: String(failure.code)
            )
            BrowserNavigationFailureDetailRow(
                label: "Loading stage",
                value: !failure.replacedDocument
                    ? String(localized: "Before content loaded")
                    : String(localized: "After content started loading")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrowserNavigationFailureMetrics.surfacePadding)
        .browserNavigationFailureCard()
        .textSelection(.enabled)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNavigationFailureTechnicalDetails(failure: BrowserNavigationFailurePreviewFixture.certificate).padding()
            .frame(width: 460)
    }
#endif
