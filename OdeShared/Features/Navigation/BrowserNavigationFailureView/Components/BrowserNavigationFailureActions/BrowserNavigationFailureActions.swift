import SwiftUI

struct BrowserNavigationFailureActions: View {
    let layout: BrowserNavigationFailureLayout
    let canGoBack: Bool
    let canProceed: Bool
    let showsDetails: Bool
    let retry: () -> Void
    let goBack: () -> Void
    let proceed: () -> Void
    let toggleDetails: () -> Void

    @ViewBuilder
    var body: some View {
        if layout.stacksActions {
            VStack(spacing: OdeSpacing.medium) {
                BrowserNavigationFailureRetryButton(action: retry)
                    .frame(maxWidth: .infinity)

                if canProceed {
                    BrowserNavigationFailureProceedButton(action: proceed)
                        .frame(maxWidth: .infinity)
                }

                if canGoBack {
                    BrowserNavigationFailureBackButton(action: goBack)
                        .frame(maxWidth: .infinity)
                }

                BrowserNavigationFailureDetailsButton(
                    showsDetails: showsDetails,
                    action: toggleDetails
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: OdeSpacing.medium) {
                BrowserNavigationFailureDetailsButton(
                    showsDetails: showsDetails,
                    action: toggleDetails
                )

                if canGoBack {
                    BrowserNavigationFailureBackButton(action: goBack)
                }

                Spacer(minLength: OdeSpacing.extraExtraLarge)

                if canProceed {
                    BrowserNavigationFailureProceedButton(action: proceed)
                }

                BrowserNavigationFailureRetryButton(action: retry)
            }
        }
    }
}
