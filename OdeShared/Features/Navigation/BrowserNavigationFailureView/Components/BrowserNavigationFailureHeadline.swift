import SwiftUI

struct BrowserNavigationFailureHeadline: View {
    let failure: PageFailure
    let presentation: BrowserNavigationFailurePresentation
    let alignment: HorizontalAlignment
    let textAlignment: TextAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: OdeSpacing.medium) {
            Text(presentation.title)
                .font(OdeTypography.display(BrowserNavigationFailureMetrics.titleSize, relativeTo: .largeTitle))
                .foregroundStyle(.primary)
                .multilineTextAlignment(textAlignment)

            presentation.message
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)

        }
    }
}

#if DEBUG
    #Preview("Offline headline") {
        let failure = BrowserNavigationFailurePreviewFixture.offline
        BrowserNavigationFailureHeadline(
            failure: failure, presentation: BrowserNavigationFailurePresentation(failure: failure), alignment: .leading,
            textAlignment: .leading
        )
        .padding().frame(width: 420)
    }
#endif
