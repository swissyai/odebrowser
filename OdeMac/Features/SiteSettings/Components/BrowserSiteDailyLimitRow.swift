import SwiftUI

/// A site's daily time limit in its site controls: off, or a number of
/// minutes a day, after which the site pauses until tomorrow.
struct BrowserSiteDailyLimitRow: View {
    let page: BrowserPage

    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        if let site = BrowserSite.of(page.live.displayURL) {
            HStack(spacing: OdeSpacing.small) {
                Label("Daily Limit", systemImage: "hourglass")
                Spacer(minLength: OdeSpacing.small)
                Picker("Daily Limit", selection: binding(for: site)) {
                    Text("Off").tag(Int?.none)
                    ForEach(choices(for: site), id: \.self) { minutes in
                        Text(BrowserFocusPauseView.duration(minutes)).tag(Int?.some(minutes))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier("site-daily-limit")
            }
        }
    }

    /// The offered limits, with the site's own when it is another.
    private func choices(for site: String) -> [Int] {
        let current = preferences.focus.limit(for: site)?.minutesPerDay
        return (FocusPreferences.offeredMinutes + [current].compactMap { $0 }).reduce(into: []) { kept, minutes in
            if !kept.contains(minutes) { kept.append(minutes) }
        }.sorted()
    }

    private func binding(for site: String) -> Binding<Int?> {
        Binding {
            preferences.focus.limit(for: site)?.minutesPerDay
        } set: { minutes in
            preferences.focus = preferences.focus.limiting(site, to: minutes)
        }
    }
}
