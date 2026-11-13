import SwiftUI

struct MobileTransientBrowsingPreviewSurface: View {
    let request: any MobileBrowserTransientRequest

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: OdeSpacing.medium) {
                Image(systemName: request.previewSystemImage)
                    .font(.largeTitle)
                Text(request.accessibilityLabel)
                    .font(.headline)
            }
            .padding(OdeSpacing.extraLarge)
            .background { OdeSurfaceLayer(shape: .rect(cornerRadius: OdeRadius.panel)) }
        }
    }
}
