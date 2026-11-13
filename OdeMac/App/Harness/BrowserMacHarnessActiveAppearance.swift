#if DEBUG || ODE_REVIEW_BUILD

    import SwiftUI

    /// Draws harness chrome in active and accessibility states without making
    /// an offscreen window key or changing the person's system preferences.
    @MainActor
    @Observable
    final class BrowserMacHarnessActiveAppearance {
        // MARK: - Static Variables

        static let shared = BrowserMacHarnessActiveAppearance()

        // MARK: - Variables

        var drawsActive = false
        var increasedContrast: Bool?
        var reduceTransparency: Bool?
    }

    struct BrowserMacHarnessActiveAppearanceModifier: ViewModifier {
        // MARK: - Variables

        @Environment(\.appearsActive) private var appearsActive

        // MARK: - Actions - Appearance

        func body(content: Content) -> some View {
            let harness = BrowserMacHarnessActiveAppearance.shared
            content
                .environment(\.appearsActive, appearsActive || harness.drawsActive)
                .environment(\.browserSpaceGroundIncreasedContrast, harness.increasedContrast)
                .environment(\.browserSpaceGroundReduceTransparency, harness.reduceTransparency)
        }
    }

#endif
