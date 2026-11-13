import SwiftUI

/// The shared Window group, plus the window choices only the desktop has:
/// light or dark, Space page motion, whether and where the pointer at the
/// window's edge brings a hidden sidebar out, and whether it stays live over a
/// page in full screen.
struct BrowserPlatformAppearanceSettingsSection: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false

    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @AppStorage(SidebarHoverRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarOnHover = SidebarHoverRevealPreference.defaultValue
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @AppStorage(SidebarFullscreenRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarInFullscreen = SidebarFullscreenRevealPreference.defaultValue

    var body: some View {
        let mode = OdeSettingValue($appearance.mode, default: BrowserLookAndFeelDefaults.appearanceMode)
        let motion = OdeSettingValue($animatesSpacePages, default: SpacePageMotionPreference.defaultValue)

        let revealWidth = OdeSettingValue(
            $appearance.sidebarRevealWidth, default: SidebarRevealWidthPreference.defaultValue)
        let reveals = OdeSettingValue($revealsSidebarOnHover, default: SidebarHoverRevealPreference.defaultValue)
        let fullscreenReveal = OdeSettingValue(
            $revealsSidebarInFullscreen, default: SidebarFullscreenRevealPreference.defaultValue)

        return BrowserWindowAppearanceGroup(
            space: space,
            showsPreview: showsPreview,
            extraSettings: [
                mode.resettable("Appearance"),
                motion.resettable("Animate pages when switching Spaces"),
                reveals.resettable("Show sidebar at window edge"),
                revealWidth.resettable("Sidebar hover area"),
                fullscreenReveal.resettable("Show sidebar on hover in full screen"),
            ],
            // Layout lists the sidebar's side, beside where tabs go.
            offersSidebarSide: false
        ) {
            OdeSettingRow("Appearance", setting: mode.resettable("Appearance")) {
                Picker("Appearance", selection: mode.binding) {
                    ForEach(BrowserAppearanceMode.all, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("appearance-mode")
            }

            OdeSettingRow(
                "Animate pages when switching Spaces",
                setting: motion.resettable("Animate pages when switching Spaces")
            ) {
                Toggle("Animate pages when switching Spaces", isOn: motion.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("animate-space-pages")
            }

            OdeSettingRow("Show sidebar at window edge", setting: reveals.resettable("Show sidebar at window edge")) {
                Toggle("Show sidebar at window edge", isOn: reveals.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("sidebar-reveals-on-hover")
            }

            OdeSettingSlider(
                "Sidebar hover area",
                value: revealWidth,
                range: SidebarRevealWidthPreference.range,
                readout: .points,
                identifier: "sidebar-reveal-width",
                onEditingChanged: { _ in SidebarRevealWidthPreview.shared.adjusted() }
            )
            .disabled(!revealsSidebarOnHover)
            .onChange(of: appearance.sidebarRevealWidth) { SidebarRevealWidthPreview.shared.adjusted() }

            OdeSettingRow(
                "Show sidebar on hover in full screen",
                setting: fullscreenReveal.resettable("Show sidebar on hover in full screen")
            ) {
                Toggle("Show sidebar on hover in full screen", isOn: fullscreenReveal.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("sidebar-fullscreen-reveal")
            }
            .disabled(!revealsSidebarOnHover)
        }
    }
}
