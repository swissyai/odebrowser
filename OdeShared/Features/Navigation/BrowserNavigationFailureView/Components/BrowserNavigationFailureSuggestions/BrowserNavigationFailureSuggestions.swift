import SwiftUI

/// What to try, on a raised card of the page's paper.
struct BrowserNavigationFailureSuggestions: View {
    let presentation: BrowserNavigationFailurePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.medium) {
            Text("Try this")
                .font(.headline)

            BrowserNavigationFailureSuggestionRow(suggestion: presentation.primarySuggestion)
            BrowserNavigationFailureSuggestionRow(suggestion: presentation.secondarySuggestion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrowserNavigationFailureMetrics.surfacePadding)
        .browserNavigationFailureCard()
    }
}

#if DEBUG
    #Preview("Certificate guidance") {
        BrowserNavigationFailureSuggestions(
            presentation: BrowserNavigationFailurePresentation(
                failure: BrowserNavigationFailurePreviewFixture.certificate)
        )
        .padding().frame(width: 420)
    }
#endif
