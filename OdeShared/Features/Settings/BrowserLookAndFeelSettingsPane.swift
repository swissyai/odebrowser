import SwiftUI

/// Device appearance edits the visible sidebar in a browser tab. Sheets retain
/// detached component previews because their browser is covered.
struct BrowserLookAndFeelSettingsPane: View {
    // MARK: - Variables

    var space: BrowserSpaceAppearance? = nil
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar

    var body: some View {
        if usesLiveSidebar {
            // The page beside the live sidebar changes size as the window
            // border is dragged, so it measures nothing that would rebuild the
            // form on every step.
            form(showsInlinePreviews: false)
                .frame(maxWidth: .infinity)
        } else {
            columns
        }
    }

    // MARK: - Actions - Layout

    /// The pinned preview beside the form where the pane has room for both,
    /// or previews in each group where it does not.
    private var columns: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(alignment: .top, spacing: 0) {
                if let columns = BrowserLookAndFeelColumns(width: width) {
                    BrowserLookAndFeelPreview(space: space, focus: .window, fillsHeight: true)
                        .frame(width: columns.preview)
                        .padding(.leading, BrowserLookAndFeelColumns.previewLeadingPadding)
                        .padding(.vertical, OdeSpacing.extraLarge)
                    form(showsInlinePreviews: false)
                        .frame(width: columns.form)
                } else {
                    form(showsInlinePreviews: true)
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private func form(showsInlinePreviews: Bool) -> some View {
        BrowserSettingsPane(.lookAndFeel) {
            #if os(macOS)
                BrowserLayoutSettingsSection()
            #endif
            BrowserPlatformAppearanceSettingsSection(space: space, showsPreview: showsInlinePreviews)
            if !usesLiveSidebar {
                BrowserDefaultPageZoomSettingsSection(
                    preferences: .shared, space: space, showsPreview: showsInlinePreviews)
            }
            BrowserTabAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
            BrowserTabStatusAppearanceGroup()
            BrowserAddressAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
            BrowserFolderAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
            if usesLiveSidebar {
                BrowserDefaultPageZoomSettingsSection(preferences: .shared, space: space, showsPreview: false)
            }
            #if os(macOS)
                BrowserSleepingTabsSettingsSection()
            #endif
            BrowserPlatformLookAndFeelResetSection()
        }
    }
}

#if os(macOS)
    /// How long a tab no window shows keeps its page loaded.
    private struct BrowserSleepingTabsSettingsSection: View {
        // MARK: - Variables

        @AppStorage(SleepingTabsPreference.key)
        private var minutes = SleepingTabsPreference.defaultValue

        var body: some View {
            let delay = OdeSettingValue($minutes, default: SleepingTabsPreference.defaultValue)

            OdeSettingsGroup(
                "Sleeping tabs",
                settings: [delay.resettable("Put tabs to sleep after")],
                footnote:
                    "Inactive pages unload and reload when reopened."
            ) {
                OdeSettingRow("Put tabs to sleep after", setting: delay.resettable("Put tabs to sleep after")) {
                    Picker("Put tabs to sleep after", selection: delay.binding) {
                        ForEach(SleepingTabsPreference.choices, id: \.self) { choice in
                            Text(title(for: choice)).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("sleep-tabs-after")
                }
                .settingsSearchTarget(.sleepingTabs)
            }
        }

        // MARK: - Actions - Labels

        private func title(for minutes: Int) -> LocalizedStringKey {
            switch minutes {
            case 5: "5 minutes"
            case 15: "15 minutes"
            case 30: "30 minutes"
            case 60: "1 hour"
            case 180: "3 hours"
            default: "Never"
            }
        }
    }
#endif
