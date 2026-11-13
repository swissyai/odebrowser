import SwiftUI

/// The foot of the sidebar while the shown Space has recent downloads: each
/// running one with its progress, size, time left and Cancel, and each file
/// that finished unseen, ready to drag out, preview with the Space bar or
/// open from its menu. It leaves once nothing is recent, and while the
/// Downloads list is open.
struct BrowserSidebarRecentDownloads: View {
    let context: BrowserSidebarContext

    /// How far a row's file name sits from the row's edge, past its icon,
    /// which the count of more downloads lines up with.
    private static let nameInset =
        OdeSpacing.extraSmall + BrowserDownloadRowPresentation.iconSide + BrowserDownloadRowPresentation.iconSpacing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.spaceColorRoles) private var spaceColorRoles
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Finished files leave on their own, so the foot looks again each minute.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let recent = recentDownloads(at: timeline.date)
            VStack(spacing: 0) {
                if let space = shownSpace,
                    BrowserRecentDownloads.isShown(recent, besides: context.utilityPresentation.surface)
                {
                    content(recent, in: space)
                        .transition(
                            reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(
                OdeMotion.collection.unlessReducingMotion(reduceMotion),
                value: BrowserRecentDownloads.isShown(recent, besides: context.utilityPresentation.surface)
                    ? recent.shown.map(\.id) : [])
        }
    }

    private func content(_ recent: BrowserRecentDownloads, in space: SpaceModel) -> some View {
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        return VStack(alignment: .leading, spacing: 0) {
            header(recent, profileID: space.profileID)
            ForEach(recent.shown) { download in
                BrowserUtilityListRow(
                    item: .download(download), assignment: assignment, actions: context.utilityActions)
            }
            if recent.moreCount > 0 {
                Button(action: showAllDownloads) {
                    Text("\(recent.moreCount) more")
                        .font(.callout)
                        .foregroundStyle(SpaceRoleStyle.secondaryText)
                        .padding(.leading, Self.nameInset)
                        .padding(.trailing, OdeSpacing.extraSmall)
                        .padding(.vertical, OdeSpacing.extraSmall)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .odeHoverSurface(cornerRadius: OdeLayout.sidebarControlCornerRadius)
                .accessibilityLabel(Text("Show \(recent.moreCount) more in Downloads"))
            }
        }
        .padding(.horizontal, BrowserSidebarMetrics.layerInset)
        .padding(.top, OdeSpacing.small)
        .padding(.bottom, OdeSpacing.extraSmall)
        .tint(accent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent Downloads")
        .accessibilityIdentifier("recent-downloads")
    }

    private func header(_ recent: BrowserRecentDownloads, profileID: UUID) -> some View {
        HStack(spacing: OdeSpacing.extraSmall) {
            Button(action: showAllDownloads) {
                // The symbol takes the rows' icon column, so the title lines
                // up with the file names under it.
                HStack(spacing: BrowserDownloadRowPresentation.iconSpacing) {
                    Image(systemName: "arrow.down.circle")
                        .frame(width: BrowserDownloadRowPresentation.iconSide)
                        .accessibilityHidden(true)
                    Text("Downloads")
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(SpaceRoleStyle.secondaryText)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Show All Downloads")
            .accessibilityHint(Text("Shows all downloads"))

            Spacer(minLength: 0)

            // A word rather than a cross, which a running row's Cancel wears.
            if recent.hasEnded {
                Button("Hide") {
                    context.pageAccess.downloadCenter.acknowledgeItems(for: profileID)
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .foregroundStyle(SpaceRoleStyle.secondaryText)
                .help("Hide Recent Downloads")
                .accessibilityLabel(Text("Hide Recent Downloads"))
            }
        }
        .padding(.horizontal, OdeSpacing.extraSmall)
        .frame(minHeight: BrowserUtilitySwitcherLayout.buttonSize)
    }

    private var shownSpace: SpaceModel? {
        guard let space = context.browser.shownSpace, !context.spaceAccess.isLocked(space) else { return nil }
        return space
    }

    private func recentDownloads(at date: Date) -> BrowserRecentDownloads {
        let center = context.pageAccess.downloadCenter
        let items = shownSpace.map { center.items(for: $0.profileID) } ?? []
        return BrowserRecentDownloads(items: items, endTime: center.endTime(of:), now: date)
    }

    /// The Space's solid accent, which a running download's ring wears.
    private var accent: Color {
        spaceColorRoles?.applying(in: colorScheme)?.accentSolid.color ?? .accentColor
    }

    private func showAllDownloads() {
        context.utilityPresentation.present(.downloads)
    }
}
