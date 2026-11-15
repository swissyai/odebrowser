import SwiftUI

/// The expected keys: physical down/up state and a separate completed outline.
struct BrowserGettingStartedTourKeycaps: View {
    // MARK: - Variables

    let keys: [String]
    let confirmed: Bool
    var pressedKeys: Set<Int> = []
    var compact = false
    var small = false
    var spokenDescription: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fontSize: CGFloat { compact ? 14 : small ? 28 : 40 }
    private var minimumWidth: CGFloat { compact ? 22 : small ? 48 : 72 }
    private var minimumHeight: CGFloat { compact ? 24 : small ? 52 : 76 }
    private var keyPadding: CGFloat { compact ? OdeSpacing.extraSmall : OdeSpacing.small }
    private var keySpacing: CGFloat { compact ? OdeSpacing.extraSmall : OdeSpacing.small }

    // MARK: - Actions - Presentation

    var body: some View {
        HStack(spacing: keySpacing) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                let pressed = pressedKeys.contains(index)
                Text(verbatim: key == "⇥" ? "⇥ Tab" : key)
                    .font(OdeTypography.sans(fontSize, weight: .medium))
                    .frame(minWidth: minimumWidth, minHeight: minimumHeight)
                    .padding(.horizontal, keyPadding)
                    .foregroundStyle(confirmed || pressed ? OdeBrandTheme.accent : OdeBrandTheme.textDisplay)
                    .odeInteractiveSurface(
                        isSelected: confirmed || pressed, isHovering: false, cornerRadius: OdeRadius.control,
                        isPressed: pressed, showsRestingSurface: true,
                        selectedBorderColor: OdeBrandTheme.accent, selectedBorderWidth: compact ? 1 : 2
                    )
                    .offset(y: pressed && !reduceMotion ? 4 : 0)
            }
        }
        .animation(OdeMotion.press.unlessReducingMotion(reduceMotion), value: pressedKeys)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenDescription ?? keys.joined(separator: " ")))
        .accessibilityValue(Text(confirmed ? "Completed" : pressedKeys.isEmpty ? "Ready" : "Pressed"))
    }
}
