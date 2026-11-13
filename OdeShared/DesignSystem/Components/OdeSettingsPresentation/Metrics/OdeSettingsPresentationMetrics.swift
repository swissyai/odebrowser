import CoreGraphics

/// Shared navigation-label and status-row geometry for Settings surfaces.
enum OdeSettingsPresentationMetrics {
    static let compactLabelSpacing: CGFloat = 9
    static let regularIconSize: CGFloat = 32
    static let compactSymbolSize: CGFloat = 12
    static let regularSymbolSize: CGFloat = 15
    static let compactIconCornerRadius = OdeCornerScale.inset
    static let regularIconCornerRadius = OdeCornerScale.control
    static let titleSpacing: CGFloat = 1
    static let statusSpacing: CGFloat = OdeSpacing.large
}
