import SwiftUI

extension EnvironmentValues {
    /// The role colors of the Space whose ground the views sit on; nil
    /// outside a Space's sidebar.
    @Entry var spaceColorRoles: SpaceColorRoles? = nil
}

/// One of a Space's role colors as a style. It draws the role where the
/// Space's own ground shows behind it, and the platform's color wherever the
/// appearance changes beneath it, as under a filled folder, or where there is
/// no Space at all.
///
/// Use `secondaryText` rather than `.secondary` for secondary text on a
/// Space's ground, `Text` values above all: a hierarchical `.secondary` set
/// on a `Text` resolves to the primary text at half strength, about 3:1 on a
/// light ground, rather than to the secondary role.
struct SpaceRoleStyle: ShapeStyle {
    enum Role: Sendable {
        case text
        case secondaryText
        case accentText
        case dangerText
        case cautionSymbol
    }

    let role: Role

    static let text = SpaceRoleStyle(role: .text)
    static let secondaryText = SpaceRoleStyle(role: .secondaryText)
    static let accentText = SpaceRoleStyle(role: .accentText)
    /// Error text, as a failed download's status, in Ode's red.
    static let dangerText = SpaceRoleStyle(role: .dangerText)
    /// The symbol of something waiting on the person, in Ode's orange.
    static let cautionSymbol = SpaceRoleStyle(role: .cautionSymbol)

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        if let roles = environment.spaceColorRoles?.applying(in: environment.colorScheme) {
            return color(in: roles).resolve(in: environment)
        }
        return fallback(in: environment).resolve(in: environment)
    }

    private func color(in roles: SpaceColorRoles) -> Color {
        switch role {
        case .text: roles.text.color
        case .secondaryText: roles.secondaryText.color
        case .accentText: roles.accentText.color
        case .dangerText: roles.dangerText.color
        case .cautionSymbol: roles.cautionSymbol.color
        }
    }

    /// The platform's colors off a Space's ground, and for the status roles
    /// a neutral Space's, which keep their floors on Ode's own canvas.
    private func fallback(in environment: EnvironmentValues) -> Color {
        switch role {
        case .text, .accentText: return .primary
        case .secondaryText: return .secondary
        case .dangerText, .cautionSymbol:
            let neutral = SpaceColorRoles(
                .graphite, colorScheme: environment.colorScheme,
                increasedContrast: environment.colorSchemeContrast == .increased)
            return color(in: neutral)
        }
    }
}

extension SpaceColorRoles {
    /// The roles that apply where a view draws in `colorScheme`, or nil
    /// where the appearance has changed beneath the Space's ground.
    func applying(in colorScheme: ColorScheme) -> SpaceColorRoles? {
        self.colorScheme == colorScheme ? self : nil
    }
}

/// Gives the views on a Space's ground its role colors: text and secondary
/// text as the foreground styles, and the roles themselves for the rows that
/// draw hover, selection, separators and the Space's name.
private struct SpaceColorRolesModifier: ViewModifier {
    let inputs: SpaceColorInputs
    var setsForeground = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                setsForeground ? AnyShapeStyle(SpaceRoleStyle.text) : AnyShapeStyle(.primary),
                setsForeground ? AnyShapeStyle(SpaceRoleStyle.secondaryText) : AnyShapeStyle(.secondary)
            )
            .environment(
                \.spaceColorRoles,
                SpaceColorRoles(
                    inputs, colorScheme: colorScheme, increasedContrast: contrast == .increased,
                    isActive: appearsActive)
            )
    }
}

extension View {
    /// Draws this content in `branding`'s role colors, over its ground.
    func spaceColorRoles(for branding: SpaceBranding) -> some View {
        modifier(SpaceColorRolesModifier(inputs: branding.colorInputs))
    }

    /// Makes `branding`'s role colors available to surfaces that are not on
    /// its ground, such as the Command Bar, without tinting their text.
    @ViewBuilder
    func spaceColorRolesAvailable(for branding: SpaceBranding?) -> some View {
        if let branding {
            modifier(SpaceColorRolesModifier(inputs: branding.colorInputs, setsForeground: false))
        } else {
            self
        }
    }
}
