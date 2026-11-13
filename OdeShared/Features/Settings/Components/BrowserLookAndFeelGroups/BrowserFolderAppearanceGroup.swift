import SwiftUI

/// How folders read in every Space on this device. A Space's own folder color
/// travels with its branding and stays in the Space editor.
struct BrowserFolderAppearanceGroup: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared

    var body: some View {
        OdeSettingsGroup(
            "Folders",
            settings: settings
        ) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .folders)
            }
        } content: {
            OdeSettingRow("Icon Only Folders", setting: icons.resettable("Icon Only Folders")) {
                Toggle("Icon Only Folders", isOn: icons.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-icon-only")
                    .help("Show a static custom icon or emoji instead of folder artwork.")
            }
            OdeSettingRow("Tint Folder Title", setting: titles.resettable("Tint Folder Title")) {
                Toggle("Tint Folder Title", isOn: titles.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-tint-title")
            }
            OdeSettingRow(
                "Always show folder highlights", setting: highlights.resettable("Always show folder highlights")
            ) {
                Toggle("Always show folder highlights", isOn: highlights.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-always-show-highlights")
            }
            OdeSettingRow("Show folder tab counts", setting: counts.resettable("Show folder tab counts")) {
                Toggle("Show folder tab counts", isOn: counts.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-show-tab-counts")
            }
            OdeSettingRow("Show folder color borders", setting: borders.resettable("Show folder color borders")) {
                Toggle("Show folder color borders", isOn: borders.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-show-color-borders")
            }
        }
    }

    private var highlights: OdeSettingValue<Bool> {
        OdeSettingValue($appearance.foldersAlwaysVisible, default: BrowserLookAndFeelDefaults.foldersAlwaysVisible)
    }

    private var counts: OdeSettingValue<Bool> {
        OdeSettingValue($appearance.foldersShowTabCounts, default: BrowserLookAndFeelDefaults.foldersShowTabCounts)
    }

    private var borders: OdeSettingValue<Bool> {
        OdeSettingValue($appearance.foldersShowBorders, default: BrowserLookAndFeelDefaults.foldersShowBorders)
    }

    private var settings: [OdeResettableSetting] {
        [
            icons.resettable("Icon Only Folders"),
            titles.resettable("Tint Folder Title"),
            highlights.resettable("Always show folder highlights"),
            counts.resettable("Show folder tab counts"),
            borders.resettable("Show folder color borders"),
        ]
    }

    private var icons: OdeSettingValue<Bool> {
        OdeSettingValue($appearance.foldersIconOnly, default: BrowserLookAndFeelDefaults.foldersIconOnly)
    }

    private var titles: OdeSettingValue<Bool> {
        OdeSettingValue($appearance.foldersTintTitle, default: BrowserLookAndFeelDefaults.foldersTintTitle)
    }
}
