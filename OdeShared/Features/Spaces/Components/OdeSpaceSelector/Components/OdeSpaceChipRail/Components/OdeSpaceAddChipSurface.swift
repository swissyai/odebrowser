import SwiftUI

struct OdeSpaceAddChipSurface<LabelContent: View>: View {
    let tint: Color
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
                    weight: .semibold
                )
            )
            .foregroundStyle(tint)
            .padding(.horizontal, OdeSpaceChipMetrics.horizontalPadding)
            .frame(height: OdeSpaceChipMetrics.height)
            .background(
                tint.opacity(
                    isPressed
                        ? OdeButtonMetrics.tintEmphasizedFill
                        : isHovering ? OdeButtonMetrics.tintRestFill : 0
                ),
                in: shape
            )
            .overlay {
                shape.strokeBorder(
                    tint.opacity(OdeButtonMetrics.tintEmphasizedStroke),
                    style: StrokeStyle(
                        lineWidth: OdeSpaceChipMetrics.restingStrokeWidth,
                        dash: OdeSpaceChipMetrics.dashPattern
                    )
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
}

#if DEBUG
    #Preview("Component") {
        OdeSpaceAddChipSurface(tint: .indigo, isPressed: false, label: Label("New Space", systemImage: "plus"))
            .padding()
    }
#endif
