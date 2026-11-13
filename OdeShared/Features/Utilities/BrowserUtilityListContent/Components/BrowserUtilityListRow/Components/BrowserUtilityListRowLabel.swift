import SwiftUI

struct BrowserUtilityListRowLabel<Icon: View, Trailing: View>: View {
    let title: String
    let subtitle: Text
    let subtitleStyle: AnyShapeStyle
    let icon: Icon
    let trailing: Trailing

    init(
        title: String,
        subtitle: Text,
        subtitleIsFailure: Bool = false,
        subtitleStyle: AnyShapeStyle? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleStyle =
            subtitleStyle
            ?? (subtitleIsFailure
                ? AnyShapeStyle(SpaceRoleStyle.dangerText)
                : AnyShapeStyle(SpaceRoleStyle.secondaryText))
        self.icon = icon()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            icon
                .foregroundStyle(SpaceRoleStyle.secondaryText)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                subtitle
                    .font(.caption)
                    .foregroundStyle(subtitleStyle)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, OdeSpacing.extraSmall)
        .padding(.vertical, OdeSpacing.small)
        .contentShape(.rect)
    }
}

extension BrowserUtilityListRowLabel where Trailing == EmptyView {
    init(
        title: String,
        subtitle: Text,
        subtitleIsFailure: Bool = false,
        subtitleStyle: AnyShapeStyle? = nil,
        @ViewBuilder icon: () -> Icon
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            subtitleIsFailure: subtitleIsFailure,
            subtitleStyle: subtitleStyle,
            icon: icon,
            trailing: EmptyView.init
        )
    }
}

#if DEBUG
    #Preview("History and failed download") {
        VStack(spacing: 16) {
            BrowserUtilityListRowLabel(title: "Ode Project Notes", subtitle: Text("odebrowser.com")) {
                Image(systemName: "doc.text.fill")
            } trailing: {
                Image(systemName: "arrow.up.right")
            }
            BrowserUtilityListRowLabel(
                title: "Ode.dmg", subtitle: Text("The connection was interrupted."), subtitleIsFailure: true
            ) {
                Image(systemName: "arrow.down.circle")
            } trailing: {
                Image(systemName: "arrow.clockwise")
            }
        }.padding().frame(width: 380)
    }
#endif
