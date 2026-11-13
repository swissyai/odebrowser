import CoreGraphics
import SwiftUI

/// Ode's corner radii, worked out from the window's own corner so nested
/// shapes stay concentric: a surface inside the window's frame, a row
/// inside a surface, an inset inside a row. Each level is the one around it
/// less the space between them, never below a floor. Every corner is drawn
/// continuous; pills use `Capsule(style: .continuous)` rather than a radius.
///
/// On a macOS 26 window (a 26 pt corner) that gives surfaces of 18, rows of
/// 10 and insets of 6.
struct OdeCornerScale: Equatable, Sendable {
    // MARK: - Static Variables

    /// The space between a window's edge and a surface inside it, and
    /// between a surface's edge and its rows.
    static let gutter: CGFloat = 8
    /// The corner a window without one, such as a full-screen window, stands
    /// in for: a surface of 14.
    static let fallbackWindow: CGFloat = 22
    /// Small and medium buttons and text fields stay this round whatever the
    /// window, as the system's own do.
    static let control: CGFloat = 8
    static let keycap: CGFloat = 5
    /// The scale of a macOS 26 window, for views that draw outside one.
    static let standard = OdeCornerScale(window: 26)
    static var surface: CGFloat { standard.surface }
    static var row: CGFloat { standard.row }
    static var inset: CGFloat { standard.inset }

    // MARK: - Variables

    /// The window's corner radius; nil in full screen.
    var window: CGFloat?

    /// Pages, the floating sidebar card, the Command Bar and other panels.
    var surface: CGFloat { max((window ?? Self.fallbackWindow) - Self.gutter, 12) }
    /// Rows and tiles inside a surface.
    var row: CGFloat { max(surface - Self.gutter, 8) }
    /// Plates, chips and selection fills inside a row.
    var inset: CGFloat { max(row - 4, 6) }
}

extension EnvironmentValues {
    /// The corner a page or floating surface rounds its web content to,
    /// which the page's host clips at the layer: SwiftUI's clip need not
    /// reach a platform view, and never reaches the remote layer Chromium
    /// draws into.
    @Entry var browserWebContentCornerRadius: CGFloat? = nil
    /// Whether the web content's top corners are the surface's, which they
    /// aren't while a bar sits above the page.
    @Entry var browserWebContentRoundsTopCorners = true
}
