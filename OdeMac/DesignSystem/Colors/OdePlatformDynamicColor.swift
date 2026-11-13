import AppKit
import SwiftUI

/// AppKit construction for shared semantic color pairs.
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
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? darkColor
                    : lightColor
            }
        )
    }

    private static func platformColor(
        _ components: OdeColorComponents,
        opacity: Double
    ) -> NSColor {
        NSColor(
            srgbRed: CGFloat(components.red) / 255,
            green: CGFloat(components.green) / 255,
            blue: CGFloat(components.blue) / 255,
            alpha: CGFloat(opacity)
        )
    }
}
