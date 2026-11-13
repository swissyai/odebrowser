import SwiftUI

/// The address field's fill, border, and how it opens the command palette,
/// on every Space on this device.
struct BrowserAddressAppearanceGroup: View {
    // MARK: - Variables

    var space: BrowserSpaceAppearance?
    var showsPreview = false

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared

    // MARK: - Actions - Presentation

    var body: some View {
        OdeSettingsGroup("Address field", settings: settings) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .addressField)
            }
        } content: {
            #if os(macOS)
                OdeSettingRow("Position", setting: placement.resettable("Position")) {
                    Picker("Address position", selection: placement.binding) {
                        ForEach(BrowserAddressPlacement.all, id: \.self) { placement in
                            Text(placement.title).tag(placement)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            #endif
            OdeSettingSlider("Color fill", value: fill, readout: .percent(zero: "None", full: "Strong"))
            OdeSettingSlider("Border", value: border, readout: .percent(zero: "None", full: "Strong"))
            OdeSettingRow(
                "Accent outline while editing",
                setting: outline.resettable("Accent outline while editing")
            ) {
                Toggle("Accent outline while editing", isOn: outline.binding)
                    .labelsHidden()
            }
            OdeSettingRow(
                "Animate into command palette",
                setting: paletteMorph.resettable("Animate into command palette")
            ) {
                Toggle("Animate into command palette", isOn: paletteMorph.binding)
                    .labelsHidden()
            }
            #if os(macOS)
                OdeSettingRow("Copy URL button", setting: copyURLButton.resettable("Copy URL button")) {
                    Toggle("Copy URL button", isOn: copyURLButton.binding)
                        .labelsHidden()
                }
            #endif
        }
    }

    // MARK: - Actions - Settings

    private var placement: OdeSettingValue<BrowserAddressPlacement> {
        OdeSettingValue($appearance.address.placement, default: BrowserLookAndFeelDefaults.address.placement)
    }

    private var fill: OdeSettingValue<Double> {
        OdeSettingValue($appearance.address.fill, default: BrowserLookAndFeelDefaults.address.fill)
    }

    private var border: OdeSettingValue<Double> {
        OdeSettingValue($appearance.address.border, default: BrowserLookAndFeelDefaults.address.border)
    }

    private var outline: OdeSettingValue<Bool> {
        OdeSettingValue(
            $appearance.address.usesAccentWhenEditing,
            default: BrowserLookAndFeelDefaults.address.usesAccentWhenEditing)
    }

    private var paletteMorph: OdeSettingValue<Bool> {
        OdeSettingValue(
            $appearance.address.animatesIntoCommandPalette,
            default: BrowserLookAndFeelDefaults.address.animatesIntoCommandPalette)
    }

    private var copyURLButton: OdeSettingValue<Bool> {
        OdeSettingValue(
            $appearance.address.showsCopyURLButton,
            default: BrowserLookAndFeelDefaults.address.showsCopyURLButton)
    }

    private var settings: [OdeResettableSetting] {
        var settings = [
            fill.resettable("Color fill"),
            border.resettable("Border"),
            outline.resettable("Accent outline while editing"),
            paletteMorph.resettable("Animate into command palette"),
        ]
        #if os(macOS)
            settings.insert(placement.resettable("Position"), at: 0)
            settings.append(copyURLButton.resettable("Copy URL button"))
        #endif
        return settings
    }
}
