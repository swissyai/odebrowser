import SwiftUI

struct BrowserImportSidebarFolderRow: View {
    let folder: FolderStateModel
    /// Whether the folder shows open, its tabs under it; closed, it shows
    /// how many it holds.
    var isOpen = true
    var tabCount = 0

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 10)
                .foregroundStyle(.secondary)
            Image(systemName: "folder.fill")
                .frame(width: 18)
                .foregroundStyle(.tint)
            Text(folder.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !isOpen, tabCount > 0 {
                Text(tabCount, format: .number)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 17)
        .padding(.trailing, 17)
        .frame(minHeight: 40)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserImportSidebarFolderRow(
            folder: SpaceModel.detached(
                SpaceState.Seed(name: "Research", folders: [FolderState.Seed(title: "Research")], tabs: [])
            ).folders.models[0]
        ).padding().frame(
            width: 300)
    }
#endif
