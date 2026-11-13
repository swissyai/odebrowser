import SwiftUI

/// The surface a field sits on, which sets the field's own fill and hairline:
/// the brand canvas setup draws, or the neutral chrome of Settings and the
/// rest of the app.
struct OdeFieldSurfaceRole: Hashable, Sendable {
    // MARK: - Static Variables

    /// Setup and the other surfaces drawn in the brand's paper and ink: the
    /// field is a well of brand canvas, outlined in the brand hairline.
    static let brand = OdeFieldSurfaceRole(
        name: "brand", fill: OdeBrandTheme.canvas, border: OdeBrandTheme.line)
    /// Settings and the rest of the platform's own surfaces: the field takes
    /// the quiet chrome surface the choice tiles rest on, outlined in the
    /// subtle border.
    static let chrome = OdeFieldSurfaceRole(
        name: "chrome", fill: OdeColor.chromeSurface, border: OdeColor.subtleBorder)

    // MARK: - Variables

    let name: String
    /// The field's own fill.
    let fill: Color
    /// The hairline around the field.
    let border: Color

    // MARK: - Initializers

    private init(name: String, fill: Color, border: Color) {
        self.name = name
        self.fill = fill
        self.border = border
    }

    // MARK: - Actions - Identity

    static func == (lhs: OdeFieldSurfaceRole, rhs: OdeFieldSurfaceRole) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

extension EnvironmentValues {
    /// The surface the fields under it sit on. A brand surface such as setup
    /// sets ``OdeFieldSurfaceRole/brand``; everything else is chrome.
    @Entry var odeFieldSurfaceRole: OdeFieldSurfaceRole = .chrome
}
