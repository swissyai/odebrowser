import CoreGraphics

/// Selection-card measurements shared by every density.
enum OdeSelectableCardMetrics {
    static let selectedBorderWidth: CGFloat = OdeLayout.pinnedAccentBorderWidth
    static let contentSpacing: CGFloat = OdeSpacing.medium
    static let selectedFillOpacity = OdeButtonMetrics.tintRestFill
    static let checkmarkSize: CGFloat = 20
    static let checkmarkSymbol = "checkmark.circle.fill"
}
