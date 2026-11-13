import SwiftUI

/// The layout choices at the top of Appearance: where windows list their
/// tabs, the sidebar's style and side, how much room rows take, and whether
/// tabs opened from a page nest under it. View and the Command Bar switch the
/// first three as well.
struct BrowserLayoutSettingsSection: View {
    @AppStorage(BrowserChromeAppearancePreference.tabLayoutKey, store: BrowserChromeAppearancePreference.defaults)
    private var tabLayout = BrowserTabLayout.defaultValue.name
    @AppStorage(BrowserChromeAppearancePreference.sidebarOnRightKey, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarOnRight = BrowserLookAndFeelDefaults.sidebarOnRight
    @AppStorage(BrowserChromeAppearancePreference.densityKey, store: BrowserChromeAppearancePreference.defaults)
    private var density = BrowserLayoutDensity.defaultValue.name
    @AppStorage(BrowserChromeAppearancePreference.sidebarStyleKey, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarStyle = BrowserSidebarStyle.defaultValue.name
    @Bindable private var appPreferences = BrowserAppPreferenceStore.shared

    var body: some View {
        let tabs = OdeSettingValue($tabLayout, default: BrowserTabLayout.defaultValue.name)
        let side = OdeSettingValue($sidebarOnRight, default: BrowserLookAndFeelDefaults.sidebarOnRight)
        let rows = OdeSettingValue($density, default: BrowserLayoutDensity.defaultValue.name)
        let style = OdeSettingValue($sidebarStyle, default: BrowserSidebarStyle.defaultValue.name)
        let nesting = OdeSettingValue(
            $appPreferences.nestsTabsOpenedFromPages, default: AppPreferences.default.nestsTabsOpenedFromPages)

        OdeSettingsGroup(
            "Layout",
            settings: [
                tabs.resettable("Tabs"), style.resettable("Sidebar"), side.resettable("Sidebar on right"),
                rows.resettable("Density"), nesting.resettable("Nest tabs opened from a page"),
            ]
        ) {
            OdeSettingRow("Tabs", setting: tabs.resettable("Tabs")) {
                Picker("Tabs", selection: tabs.binding) {
                    ForEach(BrowserTabLayout.all, id: \.self) { layout in
                        Text(layout.title).tag(layout.name)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("tab-layout")
            }
            .settingsSearchTarget(.tabLayout)

            OdeSettingRow("Sidebar", setting: style.resettable("Sidebar")) {
                Picker("Sidebar", selection: style.binding) {
                    ForEach(BrowserSidebarStyle.all, id: \.self) { style in
                        Text(style.title).tag(style.name)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("sidebar-style")
            }
            .disabled(BrowserTabLayout.named(tabLayout).showsTopBar)

            OdeSettingRow("Sidebar on right", setting: side.resettable("Sidebar on right")) {
                Toggle("Sidebar on right", isOn: side.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("sidebar-on-right")
            }
            .settingsSearchTarget(.sidebarSide)
            .disabled(BrowserTabLayout.named(tabLayout).showsTopBar)

            OdeSettingRow("Density", setting: rows.resettable("Density")) {
                Picker("Density", selection: rows.binding) {
                    ForEach(BrowserLayoutDensity.all, id: \.self) { density in
                        Text(density.title).tag(density.name)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("layout-density")
            }

            OdeSettingRow("Nest tabs opened from a page", setting: nesting.resettable("Nest tabs opened from a page")) {
                Toggle("Nest tabs opened from a page", isOn: nesting.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("nests-opened-tabs")
            }
        }
    }
}
