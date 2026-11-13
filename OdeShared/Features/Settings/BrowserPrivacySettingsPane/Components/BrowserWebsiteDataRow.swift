import SwiftUI

/// One site that keeps data in a Space: its name, what it keeps, and Remove.
struct BrowserWebsiteDataRow: View {
    let site: StoredSite
    let isRemoving: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: OdeFormRowMetrics.contentSpacing) {
            VStack(alignment: .leading, spacing: OdeFormRowMetrics.titleSpacing) {
                Text(site.site)
                    .lineLimit(1)
                Text(kinds)
                    .font(OdeTypography.metadata)
                    .foregroundStyle(OdeColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: OdeSpacing.small)
            Button("Remove", action: remove)
                .disabled(isRemoving)
                .accessibilityLabel("Remove data for \(site.site)")
        }
        .frame(minHeight: OdeFormRowMetrics.minimumHeight)
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive, action: remove)
                .odeMenuActionLabelStyle()
        }
    }

    /// What the site keeps, as a list a person reads.
    private var kinds: String {
        site.kinds.map { String(localized: $0.title) }.formatted(.list(type: .and))
    }
}
