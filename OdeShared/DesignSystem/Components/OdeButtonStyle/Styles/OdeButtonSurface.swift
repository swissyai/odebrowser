import SwiftUI

struct OdeButtonSurface: View {
    let role: OdeButtonRole
    let tint: Color?
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        rendered
            .odePressFeedback(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled
            )
            .onHover { isHovering = $0 && isEnabled }
    }

    @ViewBuilder
    private var rendered: some View {
        switch role {
        case .primary:
            primary
        case .secondary:
            secondary
        case .tertiary:
            tertiary
        case .destructive:
            destructive
        case .icon(let diameter, let isProminent):
            icon(diameter: diameter, isProminent: isProminent)
        }
    }

    private var primary: some View {
        configuration.label
            .font(
                OdeTypography.sans(
                    OdeButtonMetrics.prominentLabelSize,
                    weight: .bold
                )
            )
            // White on Ode blue measures 5.8:1.
            .foregroundStyle(Color.white)
            .padding(.horizontal, OdeButtonMetrics.prominentHorizontalPadding)
            .frame(minHeight: OdeButtonMetrics.prominentHeight)
            .background {
                Capsule().fill(
                    (tint ?? OdeBrandPalette.butter)
                        .opacity(
                            configuration.isPressed
                                ? OdeButtonMetrics.pressedFillOpacity
                                : 1
                        )
                )
            }
            .overlay {
                Capsule().strokeBorder(
                    OdeBrandPalette.ink
                        .opacity(OdeButtonMetrics.inkStrokeOpacity),
                    lineWidth: OdeButtonMetrics.strokeWidth
                )
            }
            .odeCapsuleInteractionShape()
    }

    private var secondary: some View {
        configuration.label
            .font(
                OdeTypography.sans(
                    OdeButtonMetrics.standardLabelSize,
                    weight: .semibold
                )
            )
            .foregroundStyle(OdeBrandTheme.textDisplay)
            .padding(.horizontal, OdeButtonMetrics.standardHorizontalPadding)
            .frame(minHeight: OdeButtonMetrics.standardHeight)
            .background {
                Capsule().fill(
                    configuration.isPressed || isHovering
                        ? OdeBrandTheme.surface
                        : OdeBrandTheme.canvas
                )
            }
            .overlay {
                Capsule().strokeBorder(
                    OdeBrandTheme.line,
                    lineWidth: OdeButtonMetrics.strokeWidth
                )
            }
            .odeCapsuleInteractionShape()
    }

    private var destructive: some View {
        let tint = resolvedTint
        return configuration.label
            .font(
                OdeTypography.sans(
                    OdeButtonMetrics.standardLabelSize,
                    weight: .semibold
                )
            )
            .foregroundStyle(resolvedTextTint)
            .padding(.horizontal, OdeButtonMetrics.standardHorizontalPadding)
            .frame(minHeight: OdeButtonMetrics.standardHeight)
            .background {
                Capsule().fill(tint.opacity(tintedFillOpacity(isEmphasized: false)))
            }
            .overlay {
                Capsule().strokeBorder(
                    tint.opacity(OdeButtonMetrics.tintEmphasizedStroke),
                    lineWidth: OdeButtonMetrics.strokeWidth
                )
            }
            .odeCapsuleInteractionShape()
    }

    private var tertiary: some View {
        configuration.label
            .font(OdeTypography.controlTitle)
            .foregroundStyle(resolvedTextTint)
            .padding(.horizontal, OdeButtonMetrics.quietHorizontalPadding)
            .frame(minHeight: OdeLayout.minimumHitTarget)
            .odeInteractiveSurface(
                isSelected: false,
                isHovering: isHovering,
                cornerRadius: OdeRadius.compact,
                isPressed: configuration.isPressed
            )
            .contentShape(.rect(cornerRadius: OdeRadius.compact, style: .continuous))
            .odeFocusShape(
                RoundedRectangle(cornerRadius: OdeRadius.compact, style: .continuous)
            )
    }

    private func icon(diameter: CGFloat, isProminent: Bool) -> some View {
        // A quiet glyph is a neutral action and draws in the secondary text
        // colour; only a prominent one, or one given a tint, takes a colour.
        let tint = tint ?? (isProminent ? OdeBrandTheme.accent : OdeColor.textSecondary)
        let hitTarget = max(diameter, OdeLayout.minimumHitTarget)
        return configuration.label
            .foregroundStyle(tint)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(
                    tint.opacity(tintedFillOpacity(isEmphasized: isProminent))
                )
            }
            .overlay {
                Circle().strokeBorder(
                    tint.opacity(
                        isProminent
                            ? OdeButtonMetrics.tintEmphasizedStroke
                            : OdeButtonMetrics.tintRestStroke
                    ),
                    lineWidth: isProminent
                        ? OdeButtonMetrics.prominentStrokeWidth
                        : OdeButtonMetrics.quietStrokeWidth
                )
            }
            .frame(width: hitTarget, height: hitTarget)
            .contentShape(.rect)
            .odeFocusShape(Circle())
    }

    private var resolvedTint: Color { tint ?? OdeBrandTheme.accent }
    private var resolvedTextTint: Color { tint ?? OdeBrandTheme.accentText }

    private func tintedFillOpacity(isEmphasized: Bool) -> Double {
        switch (configuration.isPressed, isEmphasized || isHovering) {
        case (true, _):
            OdeButtonMetrics.tintPressedFill
        case (false, true):
            OdeButtonMetrics.tintEmphasizedFill
        case (false, false):
            OdeButtonMetrics.tintRestFill
        }
    }
}

#if DEBUG
    #Preview("Button roles") {
        VStack(spacing: 16) {
            Button("Save Setup") {}.buttonStyle(.odePrimary)
            Button("Back") {}.buttonStyle(.odeSecondary)
            Button("Delete") {}.buttonStyle(.odeDestructive)
            Button("Manage Filter Lists") {}.buttonStyle(.odeTertiary)
            Button("Disabled") {}.buttonStyle(.odePrimary).disabled(true)
        }.padding().frame(width: 300)
    }
#endif
