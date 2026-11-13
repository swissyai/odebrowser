import SwiftUI

struct BrowserOdeImportSpaceSwitcher: View {
    let space: SpaceModel

    var body: some View {
        ZStack {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                Spacer()
                Image(systemName: "archivebox")
            }
            .foregroundStyle(.secondary)

            BrowserSpaceSymbolArtwork(space: space, size: 31, lockSize: 6, form: .tile)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(.ultraThinMaterial)
    }
}
