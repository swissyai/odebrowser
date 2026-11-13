import SwiftUI

struct OdeFieldSurface: ViewModifier {
    // MARK: - Variables

    /// Whether the field inside a field-like row has focus, as the row's
    /// owner tracks it, or nil for a surface around a native field, which
    /// tracks its own focus.
    var rowFocus: Bool?

    /// Callers may also attach a programmatic focus binding; SwiftUI keeps both
    /// bindings synchronized against the same native field.
    @FocusState private var isFocused: Bool

    @Environment(\.odeFieldSurfaceRole) private var role
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: OdeFieldMetrics.cornerRadius,
            style: .continuous
        )
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let rowFocus {
            surface(content, isFocused: rowFocus)
        } else {
            surface(content.focused($isFocused), isFocused: isFocused)
        }
    }

    // MARK: - Actions - Drawing

    private func surface(_ field: some View, isFocused: Bool) -> some View {
        field
            .padding(.horizontal, OdeFieldMetrics.horizontalPadding)
            .frame(minHeight: OdeFieldMetrics.height)
            .background(role.fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    role.border,
                    lineWidth: OdeFieldMetrics.borderWidth
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: OdeFieldMetrics.cornerRadius
                        + OdeFieldMetrics.focusRingWidth / 2,
                    style: .continuous
                )
                .strokeBorder(
                    OdeBrandTheme.accent.opacity(OdeFieldMetrics.focusRingOpacity),
                    lineWidth: OdeFieldMetrics.focusRingWidth
                )
                .padding(-OdeFieldMetrics.focusRingWidth / 2)
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
            }
            .animation(
                OdeMotion.press.unlessReducingMotion(reduceMotion),
                value: isFocused
            )
    }
}
