import SwiftUI

/// A folder in the bar of tabs on top or the sidebar as icons: its symbol,
/// with its title in the bar, opening to list the tabs it holds, however deep.
struct BrowserTopTabFolder: View {
    let folder: FolderStateModel
    let space: SpaceModel
    var showsTitle = true
    let select: (UUID) -> Void

    @Environment(OdeCore.self) private var core: OdeCore?
    @Environment(\.browserChromeAppearance) private var appearance

    var body: some View {
        Menu {
            ForEach(space.tabIDs(inFolder: folder.id), id: \.self) { tabID in
                if let tab = space.tabs.model(tabID) {
                    Button(tab.shownTitle(in: core?.state)) { select(tabID) }
                }
            }
        } label: {
            if showsTitle {
                Label(folder.title, systemImage: folder.displaySymbol)
                    .lineLimit(1)
            } else {
                Image(systemName: folder.displaySymbol)
                    .frame(width: BrowserIconSidebarMetrics.iconWidth)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(OdeChromeButtonStyle(controlSize: nil))
        .fixedSize()
        .frame(height: appearance.density.topTabHeight)
        .help(folder.title)
        .accessibilityLabel(Text("Folder \(folder.title)"))
    }
}
