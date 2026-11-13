import SwiftUI

/// A site with tab previews in its site controls: a switch that turns the
/// previews of its pinned and saved tabs on or off, while previews are on.
struct BrowserSitePreviewRow: View {
    let page: BrowserPage
    let tabPreviews: BrowserTabPreviewCenter

    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        if preferences.tabPreviews.showsPreviews, let url = page.live.displayURL,
            tabPreviews.previewSite(at: url) != nil, let site = BrowserSite.of(url)
        {
            HStack(spacing: OdeSpacing.small) {
                Label("Tab Previews", systemImage: "rectangle.stack")
                Spacer(minLength: OdeSpacing.small)
                Toggle(isOn: binding(for: site)) {
                    Text("Tab Previews")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityIdentifier("site-tab-previews-enabled")
            }
        }
    }

    private func binding(for site: String) -> Binding<Bool> {
        Binding {
            preferences.tabPreviews.showsPreviews(on: site)
        } set: { isOn in
            preferences.tabPreviews = preferences.tabPreviews.settingPreviews(isOn, on: site)
        }
    }
}
