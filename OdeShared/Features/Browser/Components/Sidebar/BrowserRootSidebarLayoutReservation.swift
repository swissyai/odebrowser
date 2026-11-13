import SwiftUI

struct BrowserRootSidebarLayoutReservation: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let isApproachingDock: Bool
    /// The width to keep whatever the presentation, such as the column of
    /// icons while the full sidebar is out over the page.
    var keptWidth: CGFloat? = nil

    var body: some View {
        Color.clear
            .frame(
                width: keptWidth
                    ?? presentation.reservedWidth(
                        for: width,
                        whileApproachingDock: isApproachingDock
                    ),
                alignment: .leading
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
