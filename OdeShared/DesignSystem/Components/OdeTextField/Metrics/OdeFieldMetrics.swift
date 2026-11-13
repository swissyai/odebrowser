import CoreGraphics

/// The single field treatment: one radius, one hairline, and one focus ring.
enum OdeFieldMetrics {
    static let cornerRadius: CGFloat = OdeRadius.control
    static let height: CGFloat = 40
    static let horizontalPadding: CGFloat = OdeSpacing.medium
    static let borderWidth: CGFloat = OdeLayout.hairline
    static let focusRingWidth: CGFloat = OdeLayout.focusRing
    static let focusRingOpacity = 0.32
}
