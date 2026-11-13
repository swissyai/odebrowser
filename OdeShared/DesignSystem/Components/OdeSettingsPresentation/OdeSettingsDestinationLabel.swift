import SwiftUI

/// Shared settings-navigation label used by the native macOS and mobile shells.
struct OdeSettingsDestinationLabel: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let systemImage: String
    let color: Color
    var compact = false
    var castsShadow = false

    var body: some View {
        HStack(spacing: labelSpacing) {
            OdeIconTile(
                systemImage: systemImage,
                color: color,
                size: iconSize,
                symbolSize: symbolSize,
                cornerRadius: iconCornerRadius,
                castsShadow: castsShadow
            )

            Text(title)
                .font(OdeTypography.controlTitle)
                .foregroundStyle(OdeColor.textPrimary)

            if compact {
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
    }

    private var labelSpacing: CGFloat {
        compact
            ? OdeSettingsPresentationMetrics.compactLabelSpacing
            : OdeSpacing.medium
    }

    private var iconSize: CGFloat {
        compact
            ? BrowserSettingsLayout.sidebarIconSize
            : OdeSettingsPresentationMetrics.regularIconSize
    }

    private var symbolSize: CGFloat {
        compact
            ? OdeSettingsPresentationMetrics.compactSymbolSize
            : OdeSettingsPresentationMetrics.regularSymbolSize
    }

    private var iconCornerRadius: CGFloat {
        compact
            ? OdeSettingsPresentationMetrics.compactIconCornerRadius
            : OdeSettingsPresentationMetrics.regularIconCornerRadius
    }
}

#if DEBUG
    #Preview("Regular and compact") {
        VStack(alignment: .leading, spacing: 20) {
            OdeSettingsDestinationLabel(
                title: "Appearance", subtitle: "Make Ode your own", systemImage: "paintpalette.fill", color: .indigo)
            OdeSettingsDestinationLabel(
                title: "Privacy", subtitle: "Control your browsing data", systemImage: "hand.raised.fill",
                color: .green, compact: true)
        }.padding().frame(width: 380)
    }
#endif
