import SwiftUI

enum BrowserSidebarWidgetActionEmphasis {
    case prominent
    case quiet
}

/// Applies Ode action styling at widget-card dimensions.
struct BrowserSidebarWidgetActionButtonStyle: ButtonStyle {
    let emphasis: BrowserSidebarWidgetActionEmphasis

    func makeBody(configuration: Configuration) -> some View {
        BrowserSidebarWidgetActionSurface(
            emphasis: emphasis,
            configuration: configuration
        )
    }
}

private struct BrowserSidebarWidgetActionSurface: View {
    let emphasis: BrowserSidebarWidgetActionEmphasis
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        rendered
            .contentShape(shape)
            .odeFocusShape(shape)
            .odePressFeedback(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled
            )
            .onHover { isHovering = $0 && isEnabled }
    }

    @ViewBuilder
    private var rendered: some View {
        switch emphasis {
        case .prominent:
            labeled
                .browserReadableForeground(over: OdeBrandTheme.accent)
                .background(
                    OdeBrandTheme.accent.opacity(
                        configuration.isPressed
                            ? OdeButtonMetrics.pressedFillOpacity
                            : 1
                    ),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        OdeBrandPalette.ink
                            .opacity(OdeButtonMetrics.inkStrokeOpacity),
                        lineWidth: OdeButtonMetrics.strokeWidth
                    )
                }
        case .quiet:
            labeled
                .foregroundStyle(.primary)
                .background {
                    OdeSurfaceLayer(
                        shape: shape,
                        hoverTint: configuration.isPressed || isHovering ? OdeColor.selection : nil
                    )
                }
                .overlay {
                    shape.strokeBorder(
                        OdeColor.subtleBorder,
                        lineWidth: OdeButtonMetrics.strokeWidth
                    )
                }
        }
    }

    private var labeled: some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .labelStyle(.titleAndIcon)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, OdeSpacing.medium)
            .padding(.vertical, OdeSpacing.extraSmall)
            .frame(
                maxWidth: .infinity,
                minHeight: BrowserSidebarWidgetDeckStyle.actionHeight
            )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: OdeRadius.control, style: .continuous)
    }
}
