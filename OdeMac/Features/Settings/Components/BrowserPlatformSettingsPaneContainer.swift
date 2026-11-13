import SwiftUI

/// The native macOS grouped form for a shared settings pane: one centred
/// column of rows.
///
/// The column is placed by ``BrowserSettingsColumnLayout``, a computed margin
/// from the page's leading edge. With horizontal scroll margins instead, macOS
/// 26 placed the rows' clicks and accessibility frames a margin away from where
/// it drew them.
///
/// While the Settings search matches settings on the page, the page scrolls
/// the first of them into view and each marks itself.
struct BrowserPlatformSettingsPaneContainer<Content: View>: View {
    @Environment(\.browserSettingsTabState) private var tabState
    @Environment(\.browserSettingsScrollKey) private var scrollKey
    @Environment(\.browserSettingsColumnWidth) private var columnWidth
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var standaloneScroll = BrowserNativeScrollState()
    let destination: BrowserSettingsDestination
    @ViewBuilder let content: Content

    init(
        destination: BrowserSettingsDestination,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        let matches = searchMatches
        BrowserSettingsColumnLayout(columnWidth: columnWidth ?? BrowserSettingsLayout.formColumnWidth) {
            ScrollViewReader { proxy in
                Form {
                    content
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .browserNativeScrollState(tabState?.scroll(forKey: scrollKey ?? destination.name) ?? standaloneScroll)
                .environment(\.browserSettingsSearchMatches, Set(matches))
                .task(id: "\(destination.name):\(tabState?.navigation.query ?? "")") {
                    guard let first = matches.first else { return }
                    // Wait for the native form to lay out its rows, but never
                    // scroll an obsolete result after the query or page changes.
                    do {
                        try await Task.sleep(for: .milliseconds(150))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    withAnimation(OdeMotion.surface.unlessReducingMotion(reduceMotion)) {
                        proxy.scrollTo(first.id, anchor: .center)
                    }
                }
            }
        }
        .accessibilityIdentifier("settings-form-\(destination.name)")
    }

    /// The settings on this page the Settings search matches, in page order.
    private var searchMatches: [BrowserSettingsSearchTarget] {
        guard let query = tabState?.navigation.query, !query.isEmpty else { return [] }
        return BrowserSettingsSearchTarget.matching(query, on: destination, locale: locale)
    }
}
