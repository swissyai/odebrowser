import CoreGraphics

/// Controlled corner radii, drawn from Ode's corner scale. Ode uses tight
/// chrome rather than pill-shaped content.
enum OdeRadius {
    static let compact = OdeCornerScale.control
    static let control = OdeCornerScale.control
    static let card = OdeCornerScale.surface
    static let panel: CGFloat = 24
}
