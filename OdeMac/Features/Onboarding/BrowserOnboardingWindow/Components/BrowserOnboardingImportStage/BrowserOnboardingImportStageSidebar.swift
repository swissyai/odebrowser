import SwiftUI

/// One Space's sidebar on the import stage: its name, its pinned tiles, its
/// saved tabs, then its open tabs, each tab's icon in the place a flying
/// icon lands on.
struct BrowserOnboardingImportStageSidebar: View {
    let space: BrowserOnboardingImportStage.Space
    let favicons: FaviconAssets
    /// How far the Space's name has faded in, from 0 to 1.
    let showsName: Double
    /// How far the rows nothing flew to have faded in, from 0 to 1.
    let showsRest: Double
    /// Whether the icon of a tab has reached its place.
    let landed: (UUID) -> Bool

    private static let tileColumns = 4
    private static let shownOpenTabs = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: space.space.settings.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(verbatim: space.name)
                    .font(OdeTypography.sans(13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(SpaceRoleStyle.accentText)
            .opacity(showsName)
            .padding(.horizontal, 6)

            if !pinned.isEmpty {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: Self.tileColumns), spacing: 6
                ) {
                    ForEach(pinned) { tab in
                        icon(tab, size: 18)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Color.primary.opacity(0.075), in: .rect(cornerRadius: OdeCornerScale.row))
                    }
                }
            }

            if !saved.isEmpty {
                VStack(spacing: 2) {
                    ForEach(saved) { tab in row(tab) }
                }
            }

            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.75)
                .padding(.horizontal, 6)
                .opacity(showsRest)

            VStack(spacing: 2) {
                ForEach(open) { tab in row(tab) }
            }
            .opacity(showsRest)
            Spacer(minLength: 0)
        }
        .padding(10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: space.countLine))
    }

    private var pinned: [TabStateModel] { Array(space.space.pinnedTabs.prefix(TabPlacement.pinnedCapacity)) }
    private var saved: [TabStateModel] { Array(space.space.savedTabs.prefix(5)) }
    private var open: [TabStateModel] {
        Array(
            space.space.tabs.models.filter { $0.placement != .pinned && $0.placement != .saved }.prefix(
                Self.shownOpenTabs))
    }

    private func row(_ tab: TabStateModel) -> some View {
        HStack(spacing: 8) {
            icon(tab, size: 15)
            Text(verbatim: tab.title)
                .font(OdeTypography.sans(12.5))
                .foregroundStyle(SpaceRoleStyle.text)
                .lineLimit(1)
                .opacity(landed(tab.id) ? 1 : showsRest)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
    }

    /// A tab's icon in its place, drawn once its flight has landed.
    private func icon(_ tab: TabStateModel, size: CGFloat) -> some View {
        TabStateFaviconView(tab: tab, favicons: favicons, profileID: space.space.profileID, size: size)
            .opacity(landed(tab.id) ? 1 : 0)
            .anchorPreference(key: BrowserOnboardingImportAnchorKey.self, value: .center) {
                [tab.id.uuidString: $0]
            }
    }
}
