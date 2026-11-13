import Foundation

/// What a compact list of tabs, the bar of tabs on top or the sidebar as
/// icons, shows for a Space, in the sidebar's order: its pinned tabs, then its
/// saved tabs and folders, then its open tabs and folders. A Split View's tabs stand side by side, and a folder is one entry
/// that opens to list its tabs.
@MainActor
struct BrowserTabStripItems {
    // MARK: - Types

    enum Entry: Identifiable {
        case tab(TabStateModel)
        case folder(FolderStateModel)

        var id: String {
            switch self {
            case .tab(let tab): "tab-\(tab.id.uuidString)"
            case .folder(let folder): "folder-\(folder.id.uuidString)"
            }
        }
    }

    // MARK: - Variables

    let pinned: [TabStateModel]
    let saved: [Entry]
    let current: [Entry]

    // MARK: - Initializers

    init(space: SpaceModel) {
        pinned = Self.entries(in: space.sidebar.section(.pinned), of: space).compactMap {
            guard case .tab(let tab) = $0 else { return nil }
            return tab
        }
        saved = Self.entries(in: space.sidebar.section(.saved), of: space)
        current = Self.entries(in: space.sidebar.section(.current), of: space)
    }

    // MARK: - Actions - Reading

    private static func entries(in list: SidebarListModel, of space: SpaceModel) -> [Entry] {
        list.rows.flatMap { row -> [Entry] in
            if row.kind.opensList {
                return space.folders.model(row.id).map { [.folder($0)] } ?? []
            }
            return row.members.compactMap { space.tabs.model($0) }.filter { !$0.isStartPage }.map(Entry.tab)
        }
    }
}
