import SwiftUI

/// Whether resting the pointer on a pinned or saved tab shows a preview of
/// its site, and for which sites.
struct BrowserTabPreviewSettingsSection: View {
    @Bindable var preferences: BrowserAppPreferenceStore

    var body: some View {
        Section {
            Toggle("Show previews of pinned and saved tabs", isOn: $preferences.tabPreviews.showsPreviews)
                .accessibilityIdentifier("tab-previews-toggle")
            if preferences.tabPreviews.showsPreviews {
                ForEach(BrowserTabPreviewSite.all, id: \.name) { site in
                    Toggle(isOn: binding(for: site)) {
                        Text(site.title)
                    }
                    .accessibilityIdentifier("tab-previews-\(site.name)-toggle")
                }
            }
        } header: {
            Text("Tab previews")
        } footer: {
            OdeFormFootnote("Read from each tab's own page and kept only on this Mac.")
        }
    }

    private func binding(for site: BrowserTabPreviewSite) -> Binding<Bool> {
        Binding {
            preferences.tabPreviews.showsPreviews(on: site.host)
        } set: { isOn in
            preferences.tabPreviews = preferences.tabPreviews.settingPreviews(isOn, on: site.host)
        }
    }
}
