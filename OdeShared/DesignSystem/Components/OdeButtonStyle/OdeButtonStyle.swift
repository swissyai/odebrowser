import SwiftUI

/// The one `ButtonStyle` Ode draws.
///
/// Built on `ButtonStyle` so keyboard activation, focus, the disabled cascade,
/// and the button accessibility trait remain system-owned.
struct OdeButtonStyle: ButtonStyle {
    let role: OdeButtonRole
    /// Space-owned surfaces can override the role's default colour. Brand chrome
    /// leaves this `nil` and inherits `OdeBrandTheme`.
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        OdeButtonSurface(role: role, tint: tint, configuration: configuration)
    }
}
