import SwiftUI

struct BrowserSourceImportSpaceHeader: View {
    let application: ImportSource?
    /// The name of the browser the review brings from.
    var title: String?
    let space: SpaceModel

    @ViewBuilder
    var body: some View {
        if application?.spaceHeaderStyle == .sectionLabel {
            HStack {
                Text(space.settings.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .help(space.settings.name)
                Spacer()
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 36)
        } else {
            HStack(spacing: 8) {
                BrowserSpaceIcon(space: space, form: .tile, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(space.settings.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .help(space.settings.name)
                    Text(title ?? application?.title ?? "Browser")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
        }
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSourceImportSpaceHeader(application: nil, space: BrowserSpaceBrandingPreviewFixture.simpleSpace)
            .padding().frame(width: 320)
    }
#endif
