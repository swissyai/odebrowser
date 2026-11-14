import SwiftUI

struct OdeSelectableCardSurface: View {
    // MARK: - Variables

    let isSelected: Bool
    let density: OdeSelectableCardDensity
    let tint: Color?
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false

    var body: some View {
        let tint = tint ?? OdeBrandTheme.accent
        let shape = OdeSelectableCardShape(cornerRadius: density.cornerRadius)

        configuration.label
            .padding(density.padding)
            .frame(maxWidth: density.fillsWidth ? .infinity : nil)
            .background(background(tint: tint), in: shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? tint : OdeBrandTheme.line,
                    lineWidth: borderWidth
                )
            }
            .contentShape(shape)
            .odeFocusShape(shape)
            .odePressFeedback(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled
            )
            .animation(
                OdeMotion.press.unlessReducingMotion(reduceMotion),
                value: isSelected
            )
            .onHover { isHovering = $0 && isEnabled }
            .odeControlPointer()
    }

    // MARK: - Actions - Drawing

    private var borderWidth: CGFloat {
        isSelected || contrast == .increased
            ? OdeSelectableCardMetrics.selectedBorderWidth
            : density.restingBorderWidth
    }

    private func background(tint: Color) -> Color {
        switch (isSelected, configuration.isPressed, isHovering) {
        case (true, true, _):
            tint.opacity(OdeButtonMetrics.tintEmphasizedFill)
        case (true, false, _):
            tint.opacity(OdeSelectableCardMetrics.selectedFillOpacity)
        case (false, true, _):
            OdeColor.selection
        case (false, false, true):
            OdeColor.hover
        case (false, false, false):
            density.showsRestingFill ? OdeColor.chromeSurface : .clear
        }
    }
}

#if DEBUG
    #Preview("Card surface") {
        @Previewable @State var selected = false
        OdeSelectableCard(isSelected: selected, accessibilityLabel: Text("Banner"), action: { selected.toggle() }) {
            Label("Banner", systemImage: "flag.fill").frame(maxWidth: .infinity, alignment: .leading)
        }.padding().frame(width: 320)
    }
#endif
