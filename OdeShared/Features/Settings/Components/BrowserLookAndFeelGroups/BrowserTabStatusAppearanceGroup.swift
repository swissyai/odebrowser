import SwiftUI

/// How tabs show what their pages are doing, such as playing sound or being
/// shared, on every Space on this device.
struct BrowserTabStatusAppearanceGroup: View {
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared

    var body: some View {
        OdeSettingsGroup("Tab status", settings: settings) {
            OdeSettingRow("Status", setting: style.resettable("Status")) {
                Picker("Status", selection: style.binding) {
                    Text("Badge").tag(BrowserTabAppearance.StatusStyle.badge)
                    Text("Replace Icon").tag(BrowserTabAppearance.StatusStyle.icon)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Status")
            }
            OdeSettingRow("Audio visualizer", setting: visualizer.resettable("Audio visualizer")) {
                Toggle("Audio visualizer", isOn: visualizer.binding)
                    .labelsHidden()
            }
        }
    }

    private var style: OdeSettingValue<BrowserTabAppearance.StatusStyle> {
        OdeSettingValue($appearance.tabs.statusStyle, default: BrowserLookAndFeelDefaults.tabs.statusStyle)
    }

    private var visualizer: OdeSettingValue<Bool> {
        OdeSettingValue(
            $appearance.tabs.showsAudioVisualizer,
            default: BrowserLookAndFeelDefaults.tabs.showsAudioVisualizer)
    }

    private var settings: [OdeResettableSetting] {
        [style.resettable("Status"), visualizer.resettable("Audio visualizer")]
    }
}
