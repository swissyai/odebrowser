import SwiftUI

/// A download row's menu entries, a divider between each group, for its
/// context menu and its actions button alike.
struct BrowserDownloadMenuItems: View {
    let menu: BrowserDownloadMenu
    let itemID: UUID
    let perform: (BrowserUtilityDownloadAction) -> Void

    var body: some View {
        ForEach(Array(menu.groups.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            ForEach(group, id: \.self) { entry in
                Button(
                    entry.title, systemImage: entry.symbol,
                    role: entry.isDestructive ? .destructive : nil
                ) {
                    perform(entry.action(for: itemID))
                }
            }
        }
        .odeMenuActionLabelStyle()
    }
}
