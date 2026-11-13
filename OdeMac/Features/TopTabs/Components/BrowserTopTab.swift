import SwiftUI

/// One tab in the bar of tabs on top: its icon and title, and a close
/// control on an open tab while the pointer rests on it or it is shown. A
/// pinned tab is its icon alone, with its title in the tooltip.
struct BrowserTopTab: View {
    let tab: TabStateModel
    let space: SpaceModel
    let favicons: FaviconAssets
    let isSelected: Bool
    var showsTitle = true
    /// The width the bar shares out to each tab with a title.
    var width: CGFloat = BrowserTopTabMetrics.idealWidth
    let select: () -> Void
    let close: () -> Void
    let togglePin: () -> Void
    let duplicate: () -> Void

    @Environment(OdeCore.self) private var core: OdeCore?
    @Environment(\.browserChromeAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            label
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if closes {
                closeButton
            }
        }
        .frame(height: appearance.density.topTabHeight)
        .odeInteractiveSurface(
            isSelected: isSelected, isHovering: isHovering, cornerRadius: appearance.cornerScale.inset
        )
        .onHover { isHovering = $0 }
        .animation(OdeMotion.hover.unlessReducingMotion(reduceMotion), value: isHovering)
        .browserOnMiddleClick { if closes { close() } }
        .help(title)
        .contextMenu {
            Button(tab.placement == .pinned ? "Unpin Tab" : "Pin Tab", systemImage: "pin", action: togglePin)
            Button("Duplicate Tab", systemImage: "plus.square.on.square", action: duplicate)
            if closes {
                Divider()
                Button("Close Tab", systemImage: "xmark", action: close)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var label: some View {
        HStack(spacing: OdeSpacing.small) {
            TabStateFaviconView(
                tab: tab, favicons: favicons, profileID: space.profileID, size: TabFaviconMetrics.defaultSize
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
            if showsTitle {
                Text(verbatim: title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Room for the close control, so the title never runs under it.
                    .padding(.trailing, closes ? BrowserTopTabMetrics.closeWidth : 0)
            }
        }
        .padding(.horizontal, showsTitle ? OdeSpacing.small : 0)
        .frame(width: showsTitle ? width : appearance.density.topTabHeight)
        .frame(maxHeight: .infinity)
        .contentShape(.rect)
        .accessibilityLabel(Text(verbatim: title))
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: BrowserTopTabMetrics.closeWidth, height: BrowserTopTabMetrics.closeWidth)
                .contentShape(.rect)
        }
        .buttonStyle(
            OdeChromeButtonStyle(
                controlSize: CGSize(
                    width: BrowserTopTabMetrics.closeWidth, height: BrowserTopTabMetrics.closeWidth))
        )
        .padding(.trailing, OdeSpacing.extraSmall)
        .opacity(isHovering || isSelected ? 1 : 0)
        .allowsHitTesting(isHovering || isSelected)
        .accessibilityLabel(Text("Close \(title)"))
    }

    /// Only an open tab closes from the bar; pinned and saved tabs stay.
    private var closes: Bool {
        showsTitle && tab.placement == .current
    }

    private var title: String {
        tab.shownTitle(in: core?.state)
    }
}

/// The sizes of a tab in the bar of tabs on top.
enum BrowserTopTabMetrics {
    static let minimumWidth: CGFloat = 76
    static let idealWidth: CGFloat = 180
    static let maximumWidth: CGFloat = 220
    static let closeWidth: CGFloat = 18
    /// The room a folder is counted at when tabs share the bar out.
    static let folderWidth: CGFloat = 120

    /// The width each tab with a title gets so that `tabs` tabs and
    /// `folders` folders fill `available` points, held between the minimum,
    /// past which the bar scrolls, and the maximum.
    static func sharedWidth(available: CGFloat, tabs: Int, folders: Int, spacing: CGFloat) -> CGFloat {
        guard tabs > 0 else { return idealWidth }
        let gaps = spacing * CGFloat(max(0, tabs + folders - 1))
        let room = available - gaps - folderWidth * CGFloat(folders)
        return min(maximumWidth, max(minimumWidth, (room / CGFloat(tabs)).rounded(.down)))
    }
}
