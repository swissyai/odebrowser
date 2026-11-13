import SwiftUI

struct BrowserSourceImportPinnedGrid: View {
    let review: BrowserImportSpaceReview
    let tabs: [TabStateModel]
    let overflowTabIDs: Set<UUID>
    let duplicateTabIDs: Set<UUID>
    let duplicateDestinationName: String?
    let setIncluded: (UUID, Bool) -> Void

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(tabs) { tab in
                let included = review.includedTabIDs.contains(tab.id)
                let overflows = overflowTabIDs.contains(tab.id) && included
                let duplicate = duplicateTabIDs.contains(tab.id)
                Button {
                    setIncluded(tab.id, !included)
                } label: {
                    TabFaviconView(
                        subject: BrowserTabFaviconSubject(tab: tab, image: nil),
                        profileID: review.sourceSpace.profileID,
                        size: 20
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 47)
                    .background(
                        duplicate
                            ? OdeBrandPalette.match.opacity(0.2)
                            : overflows
                                ? OdeColor.dangerFill
                                : Color.primary.opacity(0.075),
                        in: .rect(cornerRadius: OdeCornerScale.row, style: .continuous)
                    )
                    .overlay(alignment: .topTrailing) {
                        if duplicate || !included || overflows {
                            Image(
                                systemName: duplicate
                                    ? "equal.circle.fill"
                                    : overflows
                                        ? "exclamationmark.circle.fill"
                                        : "minus.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                duplicate
                                    ? OdeBrandPalette.match
                                    : overflows ? OdeColor.danger : Color.secondary
                            )
                            .padding(4)
                        }
                    }
                    .overlay {
                        if duplicate {
                            RoundedRectangle(cornerRadius: OdeCornerScale.row, style: .continuous)
                                .strokeBorder(
                                    OdeBrandPalette.match.opacity(0.64),
                                    lineWidth: 1
                                )
                        }
                    }
                    .opacity(duplicate || included ? 1 : 0.38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityValue(accessibilityValue(for: tab))
            }
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: PinnedTabGridLayout.columnCount(for: tabs.count)
        )
    }

    private func accessibilityValue(for tab: TabStateModel) -> String {
        let included = review.includedTabIDs.contains(tab.id)
        if overflowTabIDs.contains(tab.id), included {
            return "Included, pinned capacity full, moves to Imported Pinned Tabs"
        }
        if !included, duplicateTabIDs.contains(tab.id) {
            return "Already in \(duplicateDestinationName ?? "destination"), not included"
        }
        return included ? "Included" : "Not included"
    }
}
