import SwiftUI

/// The palette card's light in the brand color of the provider it searches.
/// Entering a provider blooms the color once around the whole card
/// (``BrowserSearchProviderBloom``), and a faint line of it stays on the
/// card's edge. Reduce Motion keeps the line alone; Reduce Transparency and
/// Increase Contrast draw no blur and a strong edge instead.
struct BrowserSearchProviderGlow: ViewModifier {
    let provider: SearchProvider?
    /// The card's outline, which the light follows as the card morphs.
    let shape: RoundedRectangle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    static func showsBlur(reduceTransparency: Bool, contrast: ColorSchemeContrast) -> Bool {
        !reduceTransparency && contrast != .increased
    }

    func body(content: Content) -> some View {
        let showsBlur = Self.showsBlur(reduceTransparency: reduceTransparency, contrast: contrast)
        let color = provider?.color.color
        let shape = shape
        content
            .background {
                if showsBlur, !reduceMotion {
                    if let heldMoment = BrowserSearchProviderBloom.heldMoment {
                        BrowserSearchProviderBloomLight(
                            shape: shape, color: color, frame: BrowserSearchProviderBloom.frame(at: heldMoment))
                    } else {
                        // Always present, so a change of provider plays the
                        // keyframes; with no provider it draws nothing.
                        Color.clear
                            .keyframeAnimator(
                                initialValue: BrowserSearchProviderBloom.Frame.rest, trigger: provider?.name
                            ) { _, frame in
                                BrowserSearchProviderBloomLight(shape: shape, color: color, frame: frame)
                            } keyframes: { _ in
                                BrowserSearchProviderBloom.keyframes
                            }
                    }
                }
            }
            .overlay {
                if let color {
                    shape.strokeBorder(
                        showsBlur
                            ? color.mix(with: .primary, by: 0.2).opacity(BrowserSearchProviderBloom.edgeOpacity)
                            : Color.primary,
                        lineWidth: showsBlur ? 1 : 1.5
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}

/// Entering a search provider: a burst of its blurred brand color blooms out
/// around the whole card, swelling with an ease-out for about a sixth of a
/// second, then fades as it drifts a little further, gone at
/// ``duration``, leaving the card's faint edge.
enum BrowserSearchProviderBloom {
    struct Frame: Equatable, Sendable {
        /// How strong the color is, from 0 to 1.
        var strength: Double
        /// How far past the card's edge the color reaches, in points.
        var spread: Double

        static let rest = Frame(strength: 0, spread: 0)
    }

    static let duration: TimeInterval = 0.65
    /// A moment to hold the bloom at, in seconds after it starts, for the
    /// test harness to capture; nil plays it as it happens.
    @MainActor static var heldMoment: TimeInterval?
    /// The color's opacity at full strength.
    static let peakOpacity = 0.8
    /// The blur at no spread, which grows with the spread.
    static let baseBlur: CGFloat = 14
    /// The brand line left on the card's edge.
    static let edgeOpacity = 0.4

    @KeyframesBuilder<Frame>
    static var keyframes: some Keyframes<Frame> {
        KeyframeTrack(\.strength) {
            LinearKeyframe(1, duration: 0.15, timingCurve: .easeOut)
            LinearKeyframe(0.9, duration: 0.07)
            LinearKeyframe(0, duration: 0.43, timingCurve: .easeIn)
        }
        KeyframeTrack(\.spread) {
            LinearKeyframe(14, duration: 0.2, timingCurve: .easeOut)
            LinearKeyframe(22, duration: 0.45, timingCurve: .easeOut)
        }
    }

    /// The bloom `time` seconds after it starts.
    static func frame(at time: TimeInterval) -> Frame {
        KeyframeTimeline(initialValue: Frame.rest) { keyframes }.value(time: time)
    }
}

/// One frame of the bloom: the card's outline grown by the spread, filled
/// with the brand color and blurred, behind the card.
private struct BrowserSearchProviderBloomLight: View {
    let shape: RoundedRectangle
    let color: Color?
    let frame: BrowserSearchProviderBloom.Frame

    var body: some View {
        if let color, frame.strength > 0 {
            shape.fill(color)
                .padding(-frame.spread)
                .blur(radius: BrowserSearchProviderBloom.baseBlur + frame.spread / 2)
                .opacity(frame.strength * BrowserSearchProviderBloom.peakOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
