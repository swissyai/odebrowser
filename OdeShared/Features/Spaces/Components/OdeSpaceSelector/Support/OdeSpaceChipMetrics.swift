import CoreGraphics

/// Shared measurements for Space chips and their rail.
enum OdeSpaceChipMetrics {
    static let baseHeight: CGFloat = 42
    static var height: CGFloat { max(baseHeight, OdeLayout.minimumHitTarget) }
    static let cornerRadius: CGFloat = OdeRadius.control
    static let horizontalPadding: CGFloat = OdeSpacing.medium
    static let contentSpacing: CGFloat = OdeSpacing.small
    static let railSpacing: CGFloat = OdeSpacing.small
    static let iconSize: CGFloat = 24
    static let menuIconSize: CGFloat = 20
    static var lockSize: CGFloat { max(5, iconSize * 0.24) }
    static let selectedStrokeWidth: CGFloat = OdeButtonMetrics.prominentStrokeWidth
    static let restingStrokeWidth: CGFloat = OdeButtonMetrics.quietStrokeWidth
    static let selectedStrokeOpacity = 0.72
    static let dashPattern: [CGFloat] = [6, 5]
}
