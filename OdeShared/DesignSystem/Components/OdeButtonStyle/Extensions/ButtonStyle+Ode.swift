import SwiftUI

extension ButtonStyle where Self == OdeButtonStyle {
    static var odePrimary: OdeButtonStyle {
        OdeButtonStyle(role: .primary)
    }

    static func odePrimary(tint: Color) -> OdeButtonStyle {
        OdeButtonStyle(role: .primary, tint: tint)
    }

    static var odeSecondary: OdeButtonStyle {
        OdeButtonStyle(role: .secondary)
    }

    static var odeTertiary: OdeButtonStyle {
        OdeButtonStyle(role: .tertiary)
    }

    static func odeTertiary(tint: Color) -> OdeButtonStyle {
        OdeButtonStyle(role: .tertiary, tint: tint)
    }

    static var odeDestructive: OdeButtonStyle {
        OdeButtonStyle(role: .destructive)
    }

    static func odeIcon(
        tint: Color? = nil,
        diameter: CGFloat = OdeButtonMetrics.iconDiameter,
        isProminent: Bool = false
    ) -> OdeButtonStyle {
        OdeButtonStyle(
            role: .icon(diameter: diameter, isProminent: isProminent),
            tint: tint
        )
    }
}
