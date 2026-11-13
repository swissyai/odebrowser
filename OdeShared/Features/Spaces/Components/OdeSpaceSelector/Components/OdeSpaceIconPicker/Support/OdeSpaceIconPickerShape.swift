import QuartzCore
import SwiftUI

/// The one shape a Space icon picker is drawn in: its track, the track's
/// border and scroll clip, and its selection, whether SwiftUI draws it or a
/// platform layer moves it with the pager. The track takes the selection's
/// own corners rather than concentric ones, so the outline and the selection
/// read as the same shape.
struct OdeSpaceIconPickerShape: InsettableShape {
    // MARK: - Static Variables

    /// The curve every corner of the picker takes: continuous, like every
    /// other corner in Ode, which a platform layer draws too.
    static let cornerStyle = RoundedCornerStyle.continuous

    /// The same curve for a platform layer that draws the selection.
    static var layerCornerCurve: CALayerCornerCurve {
        cornerStyle == .continuous ? .continuous : .circular
    }

    // MARK: - Variables

    let style: OdeSpaceIconPickerStyle
    private var insetAmount: CGFloat = 0

    // MARK: - Initializers

    init(style: OdeSpaceIconPickerStyle) {
        self.style = style
    }

    // MARK: - Actions - Drawing

    /// The corner radius of a part of the picker drawn in `rect`: the
    /// style's radius, or for touch half the part's height, so it is a
    /// capsule.
    func cornerRadius(in rect: CGRect) -> CGFloat {
        style.cornerRadius(forHeight: rect.height)
    }

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return RoundedRectangle(
            cornerRadius: max(0, cornerRadius(in: rect) - insetAmount), style: Self.cornerStyle
        )
        .path(in: inset)
    }

    func inset(by amount: CGFloat) -> OdeSpaceIconPickerShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
