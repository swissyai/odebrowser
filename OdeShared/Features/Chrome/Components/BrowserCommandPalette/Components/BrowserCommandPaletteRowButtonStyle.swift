import SwiftUI

extension EnvironmentValues {
    /// Whether the views draw on the Command Bar's selected row, whose
    /// secondary text is white rather than the panel's gray.
    @Entry var commandPaletteRowIsSelected = false
}

/// Secondary text in the Command Bar: the panel's gray on a plain row, and
/// white at the Space's secondary-label strength on the selected one. A
/// hierarchical `.secondary` would draw white at half strength there, under
/// 3:1 at every hue.
struct BrowserCommandPaletteDetailStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        guard environment.commandPaletteRowIsSelected else {
            return OdePanelDetailStyle().resolve(in: environment)
        }
        let roles = BrowserCommandPaletteRowButtonStyle.roles(in: environment)
        return Color.white.opacity(roles.commandBarSecondaryLabelOpacity).resolve(in: environment)
    }
}

extension ShapeStyle where Self == BrowserCommandPaletteDetailStyle {
    /// Secondary text in the Command Bar, on plain and selected rows alike.
    static var paletteDetail: BrowserCommandPaletteDetailStyle { BrowserCommandPaletteDetailStyle() }
}

/// A palette row: the selected one filled with a deep tone of its Space's
/// color under white text, the rest plain.
struct BrowserCommandPaletteRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Row(label: configuration.label, isSelected: isSelected)
    }

    /// The roles the selected row is drawn from: the Space's, or a neutral
    /// Space's outside one, rather than the system accent, which may be too
    /// light for white text.
    nonisolated static func roles(in environment: EnvironmentValues) -> SpaceColorRoles {
        environment.spaceColorRoles?.applying(in: environment.colorScheme)
            ?? SpaceColorRoles(
                .graphite, colorScheme: environment.colorScheme,
                increasedContrast: environment.colorSchemeContrast == .increased)
    }

    private struct Row<Label: View>: View {
        let label: Label
        let isSelected: Bool

        @Environment(\.self) private var environment
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.browserChromeAppearance) private var chromeAppearance

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: chromeAppearance.cornerScale.row, style: .continuous)
            label
                .padding(.horizontal, BrowserCommandPaletteMetrics.rowHorizontalPadding)
                .frame(minHeight: BrowserCommandPaletteMetrics.resultRowHeight)
                .contentShape(.rect)
                .modifier(SelectedForeground(color: isSelected ? .white : nil))
                .environment(\.commandPaletteRowIsSelected, isSelected)
                .background(
                    isSelected
                        ? selectionFill
                        : Color.primary.opacity(BrowserCommandPaletteMetrics.restingRowOpacity),
                    in: shape
                )
                .overlay {
                    // With Increase Contrast the selection also wears a ring
                    // in its label color, a cue beyond its fill.
                    if isSelected, contrast == .increased {
                        shape.strokeBorder(
                            Color.white.opacity(0.9),
                            lineWidth: OdeInteractiveSurfaceMetrics.increasedContrastBorderWidth)
                    }
                }
        }

        /// The Space's hue, solved deep enough for white text and its
        /// secondary label at every hue.
        private var selectionFill: Color {
            BrowserCommandPaletteRowButtonStyle.roles(in: environment).commandBarSelection.color
        }
    }

    private struct SelectedForeground: ViewModifier {
        let color: Color?

        func body(content: Content) -> some View {
            if let color { content.foregroundStyle(color) } else { content }
        }
    }
}
