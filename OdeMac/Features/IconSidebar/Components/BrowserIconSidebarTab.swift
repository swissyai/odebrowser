import SwiftUI

/// One tab in the sidebar as icons: its icon, with its title beside it while
/// the pointer rests on it, and in its tooltip.
struct BrowserIconSidebarTab: View {
    let tab: TabStateModel
    let space: SpaceModel
    let favicons: FaviconAssets
    let isSelected: Bool
    let hover: BrowserIconSidebarHover
    let select: () -> Void
    let close: () -> Void
    let togglePin: () -> Void
    let duplicate: () -> Void

    @Environment(OdeCore.self) private var core: OdeCore?
    @Environment(\.browserChromeAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var frame = CGRect.zero

    var body: some View {
        Button(action: select) {
            TabStateFaviconView(
                tab: tab, favicons: favicons, profileID: space.profileID, size: TabFaviconMetrics.defaultSize
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(
                width: BrowserIconSidebarMetrics.iconWidth,
                height: BrowserIconSidebarMetrics.rowHeight(appearance.density)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .odeInteractiveSurface(
            isSelected: isSelected, isHovering: isHovering, cornerRadius: appearance.cornerScale.inset
        )
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: { frame in
            self.frame = frame
            hover.place(tab.id, at: frame)
        }
        .onHover { isHovering in
            self.isHovering = isHovering
            if isHovering { hover.show(title, at: frame) } else { hover.leave(frame) }
        }
        .onDisappear { hover.leave(frame) }
        .animation(OdeMotion.hover.unlessReducingMotion(reduceMotion), value: isHovering)
        .browserOnMiddleClick { if tab.placement == .current { close() } }
        .help(title)
        .contextMenu {
            Button(tab.placement == .pinned ? "Unpin Tab" : "Pin Tab", systemImage: "pin", action: togglePin)
            Button("Duplicate Tab", systemImage: "plus.square.on.square", action: duplicate)
            if tab.placement == .current {
                Divider()
                Button("Close Tab", systemImage: "xmark", action: close)
            }
        }
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var title: String {
        tab.shownTitle(in: core?.state)
    }
}
