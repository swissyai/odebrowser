import SwiftUI

/// Ode's cast shares a quiet welcome; only a resting pointer sets them in motion.
struct BrowserOnboardingWelcomeIllustration: View {
    // MARK: - Variables

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.scenePhase) private var scenePhase
    @State private var isHovered = false

    private var respondsToHover: Bool {
        isHovered && capabilities.supportsHover && !reduceMotion && scenePhase == .active
    }

    // MARK: - Actions - Presentation

    var body: some View {
        HStack(alignment: .bottom, spacing: -OdeSpacing.large) {
            figure("OdeWelcomeBeret", mirrored: false, tilt: -1.5)
            figure("OdeWelcomeFriendCap", mirrored: true, tilt: 1.5)
        }
        .aspectRatio(1.5, contentMode: .fit)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 && capabilities.supportsHover && !reduceMotion && scenePhase == .active }
        .onChange(of: scenePhase) {
            if scenePhase != .active { isHovered = false }
        }
        .onChange(of: reduceMotion) {
            if reduceMotion { isHovered = false }
        }
        .onDisappear { isHovered = false }
        .accessibilityHidden(true)
    }

    private func figure(_ name: String, mirrored: Bool, tilt: Double) -> some View {
        Image(decorative: name)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .rotationEffect(.degrees(respondsToHover ? tilt : 0), anchor: .bottom)
            .offset(y: respondsToHover ? -OdeSpacing.extraExtraSmall : 0)
            .animation(
                OdeMotion.selection.unlessReducingMotion(reduceMotion || scenePhase != .active),
                value: respondsToHover
            )
    }
}

#if DEBUG
    #Preview("Welcome cast — light") {
        BrowserOnboardingWelcomeIllustration()
            .frame(width: 320)
            .padding(OdeSpacing.section)
            .background(OdeBrandTheme.canvas)
            .preferredColorScheme(.light)
    }

    #Preview("Welcome cast — dark") {
        BrowserOnboardingWelcomeIllustration()
            .frame(width: 224)
            .padding(OdeSpacing.extraExtraLarge)
            .background(OdeBrandTheme.canvas)
            .preferredColorScheme(.dark)
    }
#endif
