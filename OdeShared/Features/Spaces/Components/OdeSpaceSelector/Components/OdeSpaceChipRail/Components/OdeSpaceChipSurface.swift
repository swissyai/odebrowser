import SwiftUI

struct OdeSpaceChipSurface<LabelContent: View>: View {
    let tint: Color
    let isSelected: Bool
    let isPressed: Bool
    let label: LabelContent

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: OdeSpaceChipMetrics.cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        label
            .font(
                OdeTypography.sans(
                    OdeButtonMetrics.standardLabelSize,
                    weight: isSelected ? .bold : .medium
                )
            )
            .foregroundStyle(OdeBrandTheme.textDisplay)
            .padding(.horizontal, OdeSpaceChipMetrics.horizontalPadding)
            .frame(height: OdeSpaceChipMetrics.height)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    isSelected
                        ? tint.opacity(OdeSpaceChipMetrics.selectedStrokeOpacity)
                        : OdeBrandTheme.line,
                    lineWidth: isSelected
                        ? OdeSpaceChipMetrics.selectedStrokeWidth
                        : OdeSpaceChipMetrics.restingStrokeWidth
                )
            }
            .contentShape(
                .rect(
                    cornerRadius: OdeSpaceChipMetrics.cornerRadius,
                    style: .continuous
                )
            )
            .odeFocusShape(shape)
            .odePressFeedback(
                isPressed: isPressed,
                isEnabled: isEnabled
            )
            .onHover { isHovering = $0 && isEnabled }
    }

    private var fill: Color {
        if isSelected {
            return tint.opacity(
                isPressed
                    ? OdeButtonMetrics.tintPressedFill
                    : OdeButtonMetrics.tintEmphasizedFill
            )
        }
        if isPressed || isHovering {
            return OdeBrandTheme.surface
        }
        return OdeBrandTheme.canvas
    }
}

#if DEBUG
    #Preview("Selected and unselected") {
        HStack {
            OdeSpaceChipSurface(
                tint: .indigo, isSelected: true, isPressed: false, label: Label("Work", systemImage: "briefcase.fill"))
            OdeSpaceChipSurface(
                tint: .orange, isSelected: false, isPressed: false, label: Label("Personal", systemImage: "house.fill"))
        }.padding()
    }
#endif
