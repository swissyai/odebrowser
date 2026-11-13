import SwiftUI

/// The sites where Ode blocks nothing, in every Space, each with a way to
/// block on it again. A site gets here from its page's menu. A long list
/// offers a field that finds a site, and makes only the rows on screen.
struct BrowserBlockingSitesSettingsSection: View {
    // MARK: - Static Variables

    /// How many sites the section lists before it offers a field that finds one.
    private static let searchableCount = 10

    // MARK: - Variables

    let core: OdeCore

    @State private var query = ""

    var body: some View {
        let sites = self.sites
        let isSearchable = sites.count > Self.searchableCount
        let matches =
            query.isEmpty || !isSearchable
            ? sites : sites.filter { $0.origin.displayName.localizedStandardContains(query) }
        Section {
            if isSearchable {
                BrowserCredentialSearchField(
                    title: "Search Sites", text: $query, accessibilityIdentifier: "ad-blocking-site-search")
            }
            OdeFormRows(matches, id: \.origin) { site in
                row(site)
            }
            if sites.isEmpty {
                note("Turn blocking off from a site’s menu.")
            } else if matches.isEmpty {
                note("No Sites Found")
            }
        } header: {
            Text("Sites with Blocking Off")
        } footer: {
            Text("Ad blocking settings stay on this device.")
        }
    }

    // MARK: - Actions - Rows

    /// One row per site, however many Spaces turned it off.
    private var sites: [SiteContentBlocking] {
        var seen = Set<SiteOrigin>()
        return core.state.blockingSites.filter { seen.insert($0.origin).inserted }
    }

    private func row(_ site: SiteContentBlocking) -> some View {
        HStack(spacing: OdeFormRowMetrics.contentSpacing) {
            Text(site.origin.displayName)
                .lineLimit(1)
            Spacer(minLength: OdeSpacing.small)
            Button("Turn On Blocking", systemImage: "shield") {
                // Turning it on again from any Space turns it on everywhere.
                _ = try? core.send(SetSiteContentBlocking(spaceID: site.spaceID, origin: site.origin, blocks: true))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(OdeChromeButtonStyle())
            .accessibilityLabel("Turn on blocking for \(site.origin.displayName)")
            .help("Turn on blocking for \(site.origin.displayName)")
        }
        .frame(minHeight: OdeFormRowMetrics.minimumHeight)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(OdeColor.textSecondary)
    }
}
