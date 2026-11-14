import SwiftUI

/// A control-level pointer treatment, enabled only by the presenting surface.
struct OdeControlPointerModifier: ViewModifier {
    // MARK: - Variables

    @Environment(\.odeUsesPointingHandControls) private var usesPointingHandControls
    @Environment(\.isEnabled) private var isEnabled

    // MARK: - Actions - Presentation

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
            if usesPointingHandControls {
                content.pointerStyle(isEnabled ? .link : .default)
            } else {
                content
            }
        #else
            content
        #endif
    }
}

extension EnvironmentValues {
    @Entry var odeUsesPointingHandControls = false
}

extension View {
    /// Keeps native input and disabled-control behavior while identifying actions.
    func odeControlPointer() -> some View {
        modifier(OdeControlPointerModifier())
    }
}
