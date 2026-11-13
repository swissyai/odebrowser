import CoreGraphics
import SwiftUI

enum TabFaviconMetrics {
    static let defaultSize: CGFloat = 18
    static let emojiSizeRatio: CGFloat = 0.82
    static let emojiMinimumScaleFactor: CGFloat = 0.7
    static let minimumCornerRadius: CGFloat = 2
    static let cornerRadiusRatio: CGFloat = 0.2
    static let decodedPixelScale: CGFloat = 3
    static let minimumDecodedPixelSize = 64
    static let renderedImageScale: CGFloat = 1
    /// The plate behind an icon with color that would vanish into its ground.
    static let plateInsetRatio: CGFloat = 0.12
    static let plateCornerRatio: CGFloat = 0.25
    static let lightPlate = Color.white
    static let darkPlate = Color(red: 0.11, green: 0.11, blue: 0.118)
    /// The relative luminance of the grounds icons sit on where no surface
    /// or Space says: about #1D1D1D in dark and #F2F2F2 in light.
    static let darkGroundLuminance = 0.012
    static let lightGroundLuminance = 0.89

    static func cornerRadius(for size: CGFloat) -> CGFloat {
        max(minimumCornerRadius, size * cornerRadiusRatio)
    }

    static func maximumDecodedPixelSize(for size: CGFloat) -> Int {
        max(
            minimumDecodedPixelSize,
            Int((size * decodedPixelScale).rounded(.up))
        )
    }
}

extension EnvironmentValues {
    /// The relative luminance of what site icons are drawn on, where a
    /// surface knows it better than its Space's sidebar does.
    @Entry var browserFaviconGroundLuminance: Double? = nil
}
