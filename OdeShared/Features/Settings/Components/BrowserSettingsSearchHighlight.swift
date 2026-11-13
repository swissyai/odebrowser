import SwiftUI

/// Marks a row a Settings search landed on, while the search matches it: a
/// soft wash of the Space's accent behind the row, with a ring as well under
/// Increase Contrast. The row takes the target's scroll identity, so its
/// page can bring it into view.
struct BrowserSettingsSearchHighlight: ViewModifier {
    // MARK: - Static Variables

    static let fillOpacity = OdeOpacity.selection
    static let ringWidth = OdeLayout.focusRing
    /// How far the mark reaches past the row's content, into its insets.
    static let outset = OdeSpacing.extraSmall

    // MARK: - Variables

    let target: BrowserSettingsSearchTarget

    @Environment(\.browserSettingsSearchMatches) private var matches
    @Environment(\.browserSettingsSpaceColors) private var spaceColors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    private var isMatched: Bool { matches.contains(target) }

    /// The Space's accent as text, which reads on the Settings canvas; Ode
    /// blue outside a Space.
    private var accent: Color {
        guard let spaceColors else { return OdeBrandTheme.accentText }
        return SpaceColorRoles(spaceColors, colorScheme: colorScheme, increasedContrast: contrast == .increased)
            .accentText.color
    }

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: OdeCornerScale.inset, style: .continuous)
                shape
                    .fill(accent)
                    .opacity(isMatched ? Self.fillOpacity : 0)
                    .overlay {
                        if contrast == .increased {
                            shape.strokeBorder(accent, lineWidth: Self.ringWidth).opacity(isMatched ? 1 : 0)
                        }
                    }
                    .padding(-Self.outset)
                    .allowsHitTesting(false)
            }
            .animation(OdeMotion.surface.unlessReducingMotion(reduceMotion), value: isMatched)
            .id(target.id)
    }
}

extension EnvironmentValues {
    /// The search targets the shown Settings page's search matches.
    @Entry var browserSettingsSearchMatches: Set<BrowserSettingsSearchTarget> = []
    /// The colours of the Space a Settings tab belongs to.
    @Entry var browserSettingsSpaceColors: SpaceColorInputs? = nil
}

extension View {
    /// Marks this row as `target`, the setting a Settings search lands on.
    func settingsSearchTarget(_ target: BrowserSettingsSearchTarget) -> some View {
        modifier(BrowserSettingsSearchHighlight(target: target))
    }

    /// Marks this row as the search target named `name`, when there is one.
    @ViewBuilder
    func settingsSearchTarget(named name: String) -> some View {
        if let target = BrowserSettingsSearchTarget.named(name) {
            settingsSearchTarget(target)
        } else {
            self
        }
    }
}
