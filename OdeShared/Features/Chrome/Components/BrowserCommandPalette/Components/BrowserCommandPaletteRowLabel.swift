import SwiftUI

/// A row's one line: its title, then an em dash and what follows it in
/// secondary text, the domain for a row that opens a page, and, when the
/// person asked to see why results appear, the reason the palette ranked it
/// there. A suggestion's title sets what it adds to the typed text in bold,
/// and a tab's or page's title the parts that match it. The title keeps its
/// room and the rest truncates first.
struct BrowserCommandPaletteRowLabel: View {
    let model: BrowserCommandPaletteModel
    let row: PaletteRow
    var showsDetail = true

    var body: some View {
        let reason = showsDetail && model.preferences.showsReasons ? row.reason : nil
        let detail = showsDetail ? Self.detail(for: row) : ""
        // A title too long for the line keeps it alone, rather than leave a
        // dash with nothing after it.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: OdeSpacing.extraSmall) {
                title
                if !detail.isEmpty || reason != nil {
                    HStack(spacing: OdeSpacing.extraSmall) {
                        if !detail.isEmpty {
                            Text(verbatim: "— \(detail)")
                        }
                        if let reason {
                            if !detail.isEmpty { Text(verbatim: "·") }
                            Text(reason.text)
                        }
                    }
                    .font(BrowserCommandPaletteMetrics.rowDetailFont)
                    .foregroundStyle(.paletteDetail)
                }
            }
            title
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var title: some View {
        if let emphasized = BrowserCommandPaletteEmphasis.title(of: row) {
            Text(emphasized)
                .font(BrowserCommandPaletteMetrics.rowDetailFont)
        } else {
            Text(verbatim: row.title)
                .font(BrowserCommandPaletteMetrics.rowTitleFont)
        }
    }

    /// What follows a row's title: the domain of the page it opens, without
    /// `www.`, else its subtitle, which for a tab is its page's host and for
    /// a search what is searched; nothing when the title already says it, as
    /// "Open youtube.com" does, or for a suggestion, whose engine the search
    /// above it already names.
    static func detail(for row: PaletteRow) -> String {
        guard row.kind != .searchSuggestion else { return "" }
        let detail =
            if row.provider == nil, let address = row.address, let host = URL(string: address)?.host(), !host.isEmpty {
                domain(host)
            } else if row.tabID != nil || row.kind == .archivedTab {
                domain(row.subtitle)
            } else {
                row.subtitle
            }
        return row.title.localizedCaseInsensitiveContains(detail) ? "" : detail
    }

    private static func domain(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
