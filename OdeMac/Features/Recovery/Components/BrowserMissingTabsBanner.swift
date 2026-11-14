import SwiftUI

/// The note each window shows while a launch holds back a copy of the session
/// that had far more Spaces or tabs than the session it opened, until the
/// person restores that copy or keeps this session.
struct BrowserMissingTabsBanner: View {
    let heldCopy: BrowserHeldCopy

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let message = heldCopy.message {
            HStack(alignment: .center, spacing: OdeSpacing.medium) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: OdeSpacing.extraExtraSmall) {
                    Text("Some tabs are missing")
                        .fontWeight(.semibold)
                    Text(message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: OdeSpacing.medium)
                Button("Keep this session", action: heldCopy.keepThisSession)
                    .accessibilityIdentifier("missing-tabs-keep")
                Button("Restore that copy", action: heldCopy.restoreThatCopy)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("missing-tabs-restore")
            }
            .font(.callout)
            .padding(.horizontal, OdeSpacing.large)
            .padding(.vertical, OdeSpacing.medium)
            .frame(maxWidth: 640)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: OdeCornerScale.row, style: .continuous).fill(
                        Color(nsColor: .windowBackgroundColor))
                } else {
                    RoundedRectangle(cornerRadius: OdeCornerScale.row, style: .continuous).fill(.regularMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: OdeCornerScale.row, style: .continuous).strokeBorder(
                    .separator, lineWidth: 0.5)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("missing-tabs-banner")
        }
    }
}
