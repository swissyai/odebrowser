import SwiftUI

struct BrowserSiteExtensionsHeader: View {
    let manageExtensions: () -> Void

    var body: some View {
        HStack {
            Text("Extensions")
                .font(.headline)
            Spacer(minLength: OdeSpacing.small)
            Button(action: manageExtensions) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(
                OdeChromeButtonStyle(
                    controlSize: CGSize(
                        width: BrowserSiteControlMetrics.manageExtensionControlSize,
                        height: BrowserSiteControlMetrics.manageExtensionControlSize
                    ),
                    cornerRadius: OdeCornerScale.inset,
                    showsRestingFill: true
                )
            )
            .accessibilityLabel("Manage Extensions")
            .help("Manage Extensions")
        }
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSiteExtensionsHeader(manageExtensions: {}).padding().frame(width: 340)
    }
#endif
