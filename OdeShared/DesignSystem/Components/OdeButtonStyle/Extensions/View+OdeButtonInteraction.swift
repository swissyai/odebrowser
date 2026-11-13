import SwiftUI

extension View {
    /// Pins a custom control's keyboard focus ring to the authored shape.
    func odeFocusShape(_ shape: some Shape) -> some View {
        modifier(OdePlatformFocusShapeModifier(shape: shape))
    }

    func odeCapsuleInteractionShape() -> some View {
        contentShape(.capsule)
            .odeFocusShape(Capsule())
    }

    /// Shared press acknowledgement, disabled treatment, and Reduce Motion gate.
    func odePressFeedback(isPressed: Bool, isEnabled: Bool) -> some View {
        modifier(
            OdePressFeedbackModifier(
                isPressed: isPressed,
                isEnabled: isEnabled
            )
        )
    }
}
