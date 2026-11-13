import SwiftUI

struct MobileOnboardingTabsFeaturePage: View {
    let workSpace: SpaceModel
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?
    let primaryAction: () -> Void

    var body: some View {
        MobileOnboardingPage(
            progressIndex: 1,
            primaryTitle: "Continue",
            primarySystemImage: "chevron.right",
            primaryIdentifier:
                BrowserMobileAccessibilityID.featureNext,
            secondaryTitle: secondaryTitle,
            secondaryIdentifier:
                BrowserMobileAccessibilityID.close,
            secondaryAction: secondaryAction,
            primaryAction: primaryAction
        ) {
            VStack(spacing: MobileOnboardingLayout.tabFeaturePageSpacing) {
                MobileOnboardingTitle(title: "Tabs")

                BrowserSpaceSidebarPreview(space: workSpace)
                    .frame(
                        maxWidth: MobileOnboardingLayout.tabsPreviewWidth,
                        minHeight: MobileOnboardingLayout.tabsPreviewMinimumHeight,
                        maxHeight: MobileOnboardingLayout.tabsPreviewMaximumHeight
                    )
                    .accessibilityIdentifier(
                        BrowserMobileAccessibilityID.tabsFeature
                    )

                VStack(spacing: 0) {
                    MobileOnboardingFeatureRow(
                        symbol: "pin.fill",
                        title: "Pinned",
                        detail: "Stay at the top of the sidebar."
                    )
                    Divider()
                    MobileOnboardingFeatureRow(
                        symbol: "bookmark.fill",
                        title: "Saved",
                        detail: "Stay in the sidebar after closing."
                    )
                    Divider()
                    MobileOnboardingFeatureRow(
                        symbol: "rectangle.stack.fill",
                        title: "Open",
                        detail: "Pages move to Archive when closed."
                    )
                }
                .frame(maxWidth: MobileOnboardingLayout.featureListMaximumWidth)
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        MobileOnboardingTabsFeaturePage(
            workSpace: MobileOnboardingPreviewFixtures.tutorialWorkSpace, secondaryTitle: "Back", secondaryAction: {},
            primaryAction: {}
        ).frame(width: 390, height: 844)
    }
#endif
