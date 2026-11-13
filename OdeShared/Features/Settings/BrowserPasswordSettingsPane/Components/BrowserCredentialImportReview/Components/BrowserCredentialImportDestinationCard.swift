import SwiftUI

struct BrowserCredentialImportDestinationCard: View {
    let space: BrowserSpaceIdentity
    let format: CredentialFileFormat

    var body: some View {
        HStack(alignment: .top, spacing: OdeSpacing.large) {
            BrowserSpaceIcon(
                identity: space, form: .tile, size: BrowserCredentialImportReviewMetrics.destinationIconSize)

            VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
                Text("Importing into")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(space.name)
                    .font(.title3.weight(.semibold))
                Text(
                    "Every accepted credential will be stored only in this Space’s Keychain inventory."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: OdeSpacing.small)

            Label {
                Text(format.title)
            } icon: {
                Image(systemName: "doc.text")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, OdeSpacing.small)
            .padding(.vertical, BrowserCredentialImportReviewMetrics.formatBadgeVerticalPadding)
            .background(
                Color.primary.opacity(BrowserCredentialImportReviewMetrics.destinationFillOpacity), in: Capsule())
        }
        .padding(OdeSpacing.large)
        .background(
            Color.primary.opacity(BrowserCredentialImportReviewMetrics.destinationFillOpacity),
            in: RoundedRectangle(cornerRadius: BrowserCredentialImportReviewMetrics.destinationCardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: BrowserCredentialImportReviewMetrics.destinationCardRadius)
                .stroke(Color.secondary.opacity(BrowserCredentialImportReviewMetrics.destinationBorderOpacity))
        }
        .accessibilityElement(children: .combine)
    }
}
