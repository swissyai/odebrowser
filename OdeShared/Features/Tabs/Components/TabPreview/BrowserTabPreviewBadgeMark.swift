import SwiftUI

/// A pinned or saved tab's preview mark: how many messages wait unread, or
/// how soon the next event starts, in a small capsule of its Space's solid
/// accent. It follows the clock, so a countdown stays current.
struct BrowserTabPreviewBadgeMark: View {
    // MARK: - Static Variables

    /// The capsule's height and its type, at default density.
    static let height: CGFloat = 15
    static let fontSize: CGFloat = 10

    // MARK: - Variables

    let preview: BrowserTabPreview
    /// The title shown beside the mark, when one is: a count the title
    /// already shows, as Gmail's "Inbox (3)", is not repeated.
    var shownTitle: String? = nil

    @Environment(\.spaceColorRoles) private var spaceColorRoles
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let badge = preview.badge(at: context.date), !Self.title(shownTitle, repeats: badge.text) {
                let scale = BrowserSidebarDensity(BrowserDeviceAppearanceStore.shared.tabScale).scale
                Text(verbatim: badge.text)
                    .font(.system(size: Self.fontSize * scale, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .foregroundStyle(colors.label)
                    .padding(.horizontal, 4 * scale)
                    .frame(minWidth: Self.height * scale, minHeight: Self.height * scale)
                    .background(colors.fill, in: Capsule(style: .continuous))
                    .fixedSize()
                    .accessibilityElement()
                    .accessibilityLabel(badge.accessibilityLabel)
            }
        }
    }

    /// Whether `title` already shows `text` as a count in parentheses.
    static func title(_ title: String?, repeats text: String) -> Bool {
        guard let title else { return false }
        return title.contains("(\(text))")
    }

    /// The Space's solid accent under its label color, which holds its
    /// contrast at every hue, or the app's accent outside a Space.
    private var colors: (fill: Color, label: Color) {
        guard let roles = spaceColorRoles?.applying(in: colorScheme) else { return (.accentColor, .white) }
        return (roles.accentSolid.color, roles.labelOnSolid.color)
    }
}
