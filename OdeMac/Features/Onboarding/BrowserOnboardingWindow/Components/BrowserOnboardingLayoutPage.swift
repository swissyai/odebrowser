import SwiftUI

/// Binds confirmation to the same appearance controls as Settings. Preview
/// selection remains local to the content and writes neither value on skip.
struct BrowserOnboardingLayoutPage: View {
    // MARK: - Variables

    @AppStorage(BrowserChromeAppearancePreference.tabLayoutKey, store: BrowserChromeAppearancePreference.defaults)
    private var storedLayout = BrowserTabLayout.defaultValue.name
    @AppStorage(BrowserChromeAppearancePreference.sidebarOnRightKey, store: BrowserChromeAppearancePreference.defaults)
    private var storedRight = BrowserLookAndFeelDefaults.sidebarOnRight

    let back: BrowserOnboardingBackAction
    let continueSetup: () -> Void

    // MARK: - Actions - Presentation

    var body: some View {
        BrowserOnboardingLayoutContent(
            storedLayout: $storedLayout, storedRight: $storedRight,
            addressPlacement: BrowserDeviceAppearanceStore.shared.address.placement,
            back: back, continueSetup: continueSetup)
    }
}
