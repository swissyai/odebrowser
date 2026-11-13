import SwiftUI

struct MobileOnboardingSyncFeaturePage: View {
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?
    let primaryAction: () -> Void

    var body: some View {
        MobileOnboardingPage(
            progressIndex: 2,
            primaryTitle: "Set Up Spaces",
            primarySystemImage: "chevron.right",
            primaryIdentifier:
                BrowserMobileAccessibilityID.featureNext,
            secondaryTitle: secondaryTitle,
            secondaryIdentifier:
                BrowserMobileAccessibilityID.close,
            secondaryAction: secondaryAction,
            primaryAction: primaryAction
        ) {
            VStack(spacing: MobileOnboardingLayout.syncFeaturePageSpacing) {
                MobileOnboardingTitle(title: "iCloud Sync")

                Image(systemName: "laptopcomputer.and.iphone")
                    .font(
                        .system(
                            size: MobileOnboardingLayout.syncSymbolSize,
                            weight: .light
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(
                        width: MobileOnboardingLayout.syncSymbolFrame,
                        height: MobileOnboardingLayout.syncSymbolFrame
                    )
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: .circle
                    )
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    MobileOnboardingFeatureRow(
                        symbol: "lock.shield.fill",
                        title: "Space groups",
                        detail: "Sub-Spaces share their primary Space’s history, passwords and site data."
                    )
                    Divider()
                    MobileOnboardingFeatureRow(
                        symbol: "laptopcomputer",
                        title: "Import on Mac",
                        detail: "Import on your Mac, then sync with iCloud."
                    )
                }
                .frame(maxWidth: MobileOnboardingLayout.featureListMaximumWidth)
                .accessibilityIdentifier(
                    BrowserMobileAccessibilityID.syncFeatureList
                )
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        MobileOnboardingSyncFeaturePage(secondaryTitle: "Back", secondaryAction: {}, primaryAction: {}).frame(
            width: 390, height: 844)
    }
#endif
