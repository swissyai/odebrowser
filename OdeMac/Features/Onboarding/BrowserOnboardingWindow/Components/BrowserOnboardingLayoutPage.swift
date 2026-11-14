import SwiftUI

/// Binds confirmation to the same appearance controls as Settings. Preview
/// selection remains local to the content and writes neither value on skip.
struct BrowserOnboardingLayoutPage: View {
    // MARK: - Variables

    @AppStorage(BrowserChromeAppearancePreference.tabLayoutKey, store: BrowserChromeAppearancePreference.defaults)
    private var storedLayout = BrowserTabLayout.defaultValue.name

    private let appearance: BrowserDeviceAppearanceStore

    let back: BrowserOnboardingBackAction
    let continueSetup: () -> Void

    init(
        back: BrowserOnboardingBackAction, continueSetup: @escaping () -> Void,
        appearance: BrowserDeviceAppearanceStore = .shared,
        defaults: UserDefaults = BrowserChromeAppearancePreference.defaults
    ) {
        self.back = back
        self.continueSetup = continueSetup
        self.appearance = appearance
        _storedLayout = AppStorage(
            wrappedValue: BrowserTabLayout.defaultValue.name,
            BrowserChromeAppearancePreference.tabLayoutKey, store: defaults)
    }

    func confirmSelection(_ selection: BrowserOnboardingTabPlacement) {
        storedLayout = selection.layout.name
        if !selection.layout.showsTopBar { appearance.sidebarOnRight = selection.onRight }
        continueSetup()
    }

    // MARK: - Actions - Presentation

    var body: some View {
        BrowserOnboardingLayoutContent(
            storedLayout: storedLayout, storedRight: appearance.sidebarOnRight,
            addressPlacement: appearance.address.placement,
            back: back, continueSetup: continueSetup, confirmLayout: confirmSelection)
    }
}
