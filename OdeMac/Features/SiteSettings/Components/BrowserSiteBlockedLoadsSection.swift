import SwiftUI

/// What content blocking stopped on the page: the person's choice to block on
/// this site or not, which the core keeps for the page's Space on every
/// engine, and on WebKit a count and the sites the loads came from.
struct BrowserSiteBlockedLoadsSection: View {
    let page: BrowserPage
    @State private var isExpanded: Bool
    @Environment(OdeCore.self) private var core: OdeCore?

    init(page: BrowserPage, isExpanded: Bool = false) {
        self.page = page
        _isExpanded = State(initialValue: isExpanded)
    }

    /// The page's site as the core switches it, or nil where the page's Space
    /// blocks nothing or the page shows no website.
    private var siteSwitch: SiteContentBlockingSwitch? {
        guard let core else { return nil }
        // Reading the sites keeps the switch current when they change.
        _ = core.state.blockingSites
        return SiteContentBlockingSwitch(core: core, spaceID: page.spaceID, url: page.live.displayURL)
    }

    var body: some View {
        let siteSwitch = siteSwitch
        VStack(alignment: .leading, spacing: OdeSpacing.small) {
            Toggle(isOn: blocksOnSite(siteSwitch)) {
                Text("Block ads and trackers on this site")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(siteSwitch == nil)
            .accessibilityIdentifier("site-blocks-content")

            summary(blocks: siteSwitch?.blocks)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func summary(blocks: Bool?) -> some View {
        let blocked = page.blockedLoads
        if blocks == nil {
            Text("Ad blocking is off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if blocks == false {
            Text("Ode isn’t blocking anything on this site.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if page.webKitAdapter == nil {
            EmptyView()
        } else if blocked.total == 0 {
            Text("Nothing blocked on this page so far.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("site-blocked-summary")
        } else {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: OdeSpacing.small) {
                    Text(summaryText(total: blocked.total, sites: blocked.sites.count))
                        .font(.caption)
                    Spacer(minLength: OdeSpacing.small)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("site-blocked-summary")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                ForEach(blocked.sites, id: \.site) { entry in
                    HStack {
                        Text(verbatim: entry.site)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: OdeSpacing.small)
                        Text(entry.count, format: .number)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func summaryText(total: Int, sites: Int) -> String {
        switch (total, sites) {
        case (1, _):
            String(localized: "Blocked 1 load", comment: "Content blocking stopped one load on the page.")
        case (_, 1):
            String(
                localized: "Blocked \(total) loads from 1 site",
                comment: "Content blocking stopped several loads, all from one site.")
        default:
            String(
                localized: "Blocked \(total) loads from \(sites) sites",
                comment: "How much content blocking stopped on the page, with the number of loads and of sites.")
        }
    }

    /// Turns blocking off or on for the page's site in its Space, then brings
    /// the Space's pages in line and reloads this one so the change shows.
    private func blocksOnSite(_ siteSwitch: SiteContentBlockingSwitch?) -> Binding<Bool> {
        Binding(
            get: { siteSwitch?.blocks ?? false },
            set: { blocks in
                guard let core, let siteSwitch, siteSwitch.blocks != blocks,
                    (try? core.send(siteSwitch.intent)) != nil
                else { return }
                Task {
                    await page.host?.reconcileContentBlocking()
                    page.reload()
                }
            })
    }
}
