import SwiftUI
import UIKit

/// UIKit construction for shared semantic color pairs.
enum OdePlatformDynamicColor {
    static func make(
        light: OdeColorComponents,
        lightOpacity: Double,
        dark: OdeColorComponents,
        darkOpacity: Double
    ) -> Color {
        let lightColor = platformColor(light, opacity: lightOpacity)
        let darkColor = platformColor(dark, opacity: darkOpacity)
        return Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? darkColor : lightColor
            }
        )
    }

    private static func platformColor(
        _ components: OdeColorComponents,
        opacity: Double
    ) -> UIColor {
        UIColor(
            red: CGFloat(components.red) / 255,
            green: CGFloat(components.green) / 255,
            blue: CGFloat(components.blue) / 255,
            alpha: CGFloat(opacity)
        )
    }
}
