import SwiftUI

struct BrowserSettingsPrivateSpaceIdentity: View {
    // MARK: - Variables

    let space: BrowserSpaceIdentity

    // MARK: - Initializers

    init(space: some BrowserSpaceIdentifying) {
        self.space = space.identity
    }

    // MARK: - Body

    var body: some View {
        Group {
            BrowserSpaceSymbolArtwork(identity: space, size: 34, lockSize: 8, form: .tile)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: OdeFormRowMetrics.titleSpacing) {
                Text(space.name)
                    .font(OdeTypography.controlTitle)
                Text("Private Space")
                    .font(OdeTypography.metadata)
                    .foregroundStyle(OdeColor.textSecondary)
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSettingsPrivateSpaceIdentity(space: BrowserSpaceBrandingPreviewFixture.guardedSpace).padding().frame(
            width: 360)
    }
#endif
