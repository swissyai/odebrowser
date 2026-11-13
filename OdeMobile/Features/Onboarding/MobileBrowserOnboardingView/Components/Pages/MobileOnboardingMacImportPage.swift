import SwiftUI

struct MobileOnboardingMacImportPage: View {
    let close: () -> Void
    let reviewFeatures: () -> Void

    var body: some View {
        MobileOnboardingPage(
            progressIndex: nil,
            primaryTitle: "Review Features",
            primarySystemImage: "chevron.right",
            primaryIdentifier:
                BrowserMobileAccessibilityID
                .macImportReviewFeatures,
            secondaryTitle: "Close",
            secondaryIdentifier:
                BrowserMobileAccessibilityID.close,
            secondaryAction: close,
            primaryAction: reviewFeatures
        ) {
            VStack(spacing: MobileOnboardingLayout.macImportPageSpacing) {
                Spacer(
                    minLength: MobileOnboardingLayout.macImportMinimumSpacing
                )

                HStack(spacing: MobileOnboardingLayout.macImportSymbolSpacing) {
                    Image(systemName: "laptopcomputer")
                    Image(systemName: "icloud.fill")
                        .foregroundStyle(.tint)
                    Image(systemName: "iphone")
                }
                .font(
                    .system(
                        size: MobileOnboardingLayout.macImportSymbolSize,
                        weight: .light
                    )
                )
                .accessibilityHidden(true)

                MobileOnboardingTitle(
                    title: "Import on Mac",
                    detail: "Import supported browsers on a Mac, then use iCloud sync to bring your Spaces here."
                )
                .accessibilityIdentifier(
                    BrowserMobileAccessibilityID.macImportContent
                )

                Spacer(
                    minLength: MobileOnboardingLayout.macImportMinimumSpacing
                )
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        MobileOnboardingMacImportPage(close: {}, reviewFeatures: {}).frame(width: 390, height: 844)
    }
#endif
