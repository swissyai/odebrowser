import SwiftUI

struct BrowserSoftwareUpdateReleaseNoteBlock: View {
    let block: BrowserSoftwareUpdateReleaseNotesDocument.Block

    @ViewBuilder
    var body: some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text)
                .font(headingFont(level: level))
                .padding(.top, level <= 2 ? OdeSpacing.small : OdeSpacing.extraSmall)
        case .paragraph:
            Text(block.text)
                .font(.body)
                .lineSpacing(OdeSpacing.extraExtraSmall)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: OdeSpacing.small) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5, weight: .semibold))
                    .foregroundStyle(OdeBrandTheme.accent)
                    .accessibilityHidden(true)

                Text(block.text)
                    .font(.body)
                    .lineSpacing(OdeSpacing.extraExtraSmall)
            }
        case .divider:
            Divider()
                .padding(.vertical, OdeSpacing.extraSmall)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1, 2: .title3.weight(.semibold)
        case 3: .headline
        default: .subheadline.weight(.semibold)
        }
    }
}
