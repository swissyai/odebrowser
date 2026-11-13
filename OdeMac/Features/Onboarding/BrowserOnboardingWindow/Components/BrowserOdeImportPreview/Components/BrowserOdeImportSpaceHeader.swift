import SwiftUI

struct BrowserOdeImportSpaceHeader: View {
    let space: SpaceModel

    var body: some View {
        HStack(spacing: 8) {
            BrowserSpaceIcon(space: space, form: .tile, size: 22)
            Text(space.settings.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .help(space.settings.name)
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .frame(minHeight: 36)
    }
}
