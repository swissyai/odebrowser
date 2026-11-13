import SwiftUI

/// Ode's mark on its tile, as the app icon draws it: the wave peel on a warm
/// ground, for the Start Page and the welcome screen, with the curl shadow
/// when the tile is large enough to show it.
struct OdeStartPageMark: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    @State private var lift: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let tile = RoundedRectangle(
                cornerRadius: side * OdeStartPageMarkMetrics.cornerRadiusRatio,
                style: .continuous
            )

            ZStack {
                tile.fill(OdeStartPageMarkPalette(colorScheme: colorScheme).background)
                OdeMark(placement: .onCanvas, finish: .curlShadow, lift: lift)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .overlay {
                tile.strokeBorder(
                    .primary.opacity(OdeStartPageMarkMetrics.borderOpacity),
                    lineWidth: OdeStartPageMarkMetrics.borderWidth
                )
                .frame(width: side, height: side)
            }
        }
        .onAppear {
            guard OdeMarkDip.session.claim(reduceMotion: reduceMotion, isActive: appearsActive) else { return }
            lift = 1
            Task { @MainActor in
                withAnimation(OdeMotion.markDip) { lift = 0 }
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        OdeStartPageMark().frame(width: 80, height: 80).padding()
    }
#endif
