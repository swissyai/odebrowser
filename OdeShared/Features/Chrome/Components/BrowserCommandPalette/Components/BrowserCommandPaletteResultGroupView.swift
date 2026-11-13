import SwiftUI

struct BrowserCommandPaletteResultGroupView: View {
    let model: BrowserCommandPaletteModel
    let group: BrowserCommandPaletteGroup
    var listsUpward = false

    @ViewBuilder
    var body: some View {
        if let header = group.section.title {
            VStack(
                alignment: .leading,
                spacing: BrowserCommandPaletteMetrics.resultHeaderSpacing
            ) {
                Text(header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.paletteDetail)
                    .padding(
                        .horizontal,
                        BrowserCommandPaletteMetrics.resultHeaderHorizontalPadding
                    )
                BrowserCommandPaletteResultRows(model: model, group: group, listsUpward: listsUpward)
            }
        } else {
            VStack(alignment: .leading, spacing: BrowserCommandPaletteMetrics.resultRowSpacing) {
                BrowserCommandPaletteResultRows(model: model, group: group, listsUpward: listsUpward)
            }
        }
    }
}
