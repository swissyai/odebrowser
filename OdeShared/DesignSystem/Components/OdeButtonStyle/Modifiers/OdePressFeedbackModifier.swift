import SwiftUI

struct OdePressFeedbackModifier: ViewModifier {
    let isPressed: Bool
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                (isPressed ? OdeButtonMetrics.pressedScale : 1).unlessReducingMotion(reduceMotion)
            )
            .opacity(isEnabled ? 1 : OdeButtonMetrics.disabledOpacity)
            .animation(
                OdeMotion.press.unlessReducingMotion(reduceMotion),
                value: isPressed
            )
    }
}
