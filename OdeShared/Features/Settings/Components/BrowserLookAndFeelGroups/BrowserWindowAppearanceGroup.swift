import SwiftUI

/// The window's frame: how much of the Space shows around a page, which side
/// the sidebar sits on, how its Space icons are sized, and the accent its tabs
/// and address field wear.
///
/// The desktop hands in the choices only it has — focused-window transparency
/// and Space page motion — as extra rows and the settings that go with them, so
/// the group's own Reset covers them too.
struct BrowserWindowAppearanceGroup<Extra: View>: View {
    // MARK: - Variables

    var space: BrowserSpaceAppearance?
    var showsPreview = false
    var extraSettings: [OdeResettableSetting] = []
    /// Whether the group offers the sidebar's side, which a shell with its own
    /// Layout group lists there instead.
    var offersSidebarSide = true
    @ViewBuilder var extraRows: () -> Extra

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared

    // MARK: - Actions - Drawing

    var body: some View {
        OdeSettingsGroup(
            "Window",
            settings: settings
        ) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .window)
            }
        } content: {
            OdeSettingSlider(
                "Window border",
                value: border,
                range: BrowserChromeAppearance.borderWidthRange,
                readout: .points(zero: "Borderless"),
                identifier: "window-border-width"
            )
            .settingsSearchTarget(.windowBorder)
            OdeSettingSlider(
                "Material",
                value: material,
                range: 0...Double(OdeSurfaceMaterial.all.count - 1),
                step: 1,
                readout: OdeSettingSliderReadout {
                    String(localized: OdeSurfaceMaterial.at(position: Int($0.rounded())).title)
                },
                identifier: "surface-material"
            )
            if offersSidebarSide {
                OdeSettingRow("Sidebar on right", setting: sidebar.resettable("Sidebar on right")) {
                    Toggle("Sidebar on right", isOn: sidebar.binding)
                        .labelsHidden()
                        .accessibilityIdentifier("sidebar-on-right")
                }
            }
            OdeSettingRow(
                "Fit Space icons to sidebar", setting: fitsSpaceIcons.resettable("Fit Space icons to sidebar")
            ) {
                Toggle("Fit Space icons to sidebar", isOn: fitsSpaceIcons.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("space-icons-fit-sidebar")
            }
            OdeSettingSlider(
                "Space icon size",
                value: spaceIconScale,
                range: BrowserSpaceIconSizing.scaleRange,
                step: BrowserSpaceIconSizing.scaleStep,
                identifier: "space-icon-size"
            )
            .disabled(appearance.spaceIconSizing.fitsStrip)
            BrowserAppearanceAccentRow(
                color: accent,
                fallback: space?.branding.primaryColor ?? .indigo,
                identifier: "follows-space-accent"
            )
            extraRows()
        }
    }

    // MARK: - Actions - Settings

    private var border: OdeSettingValue<Double> {
        OdeSettingValue($appearance.windowBorderWidth, default: BrowserLookAndFeelDefaults.windowBorderWidth)
    }

    /// The sidebar's layer material, as a position from Ultra Thin to Ultra Thick.
    private var material: OdeSettingValue<Double> {
        OdeSettingValue(
            Binding(
                get: { Double(appearance.surfaceMaterial.position) },
                set: { appearance.surfaceMaterial = .at(position: Int($0.rounded())) }
            ),
            default: Double(BrowserLookAndFeelDefaults.surfaceMaterial.position)
        )
    }

    private var sidebar: OdeSettingValue<Bool> {
        OdeSettingValue($appearance.sidebarOnRight, default: BrowserLookAndFeelDefaults.sidebarOnRight)
    }

    /// Whether the Space switcher fits its icons to the sidebar, or keeps the
    /// size below.
    private var fitsSpaceIcons: OdeSettingValue<Bool> {
        OdeSettingValue(
            Binding(
                get: { appearance.spaceIconSizing.fitsStrip },
                set: { appearance.spaceIconSizing = $0 ? .automatic : .manual }
            ),
            default: BrowserLookAndFeelDefaults.spaceIconSizing.fitsStrip
        )
    }

    private var spaceIconScale: OdeSettingValue<Double> {
        OdeSettingValue($appearance.spaceIconScale, default: BrowserLookAndFeelDefaults.spaceIconScale)
    }

    /// One accent for the selected tabs, pins and the address field, which
    /// keep their own stored colors.
    private var accent: OdeSettingValue<BrandColor?> {
        OdeSettingValue(
            Binding(
                get: { appearance.tabs.color ?? appearance.address.color },
                set: { color in
                    appearance.tabs.color = color
                    appearance.address.color = color
                }
            )
        )
    }

    private var settings: [OdeResettableSetting] {
        [border.resettable("Window border"), material.resettable("Material")]
            + (offersSidebarSide ? [sidebar.resettable("Sidebar on right")] : [])
            + [
                fitsSpaceIcons.resettable("Fit Space icons to sidebar"),
                spaceIconScale.resettable("Space icon size"),
                accent.resettable("Follow Space accent"),
            ] + extraSettings
    }
}
