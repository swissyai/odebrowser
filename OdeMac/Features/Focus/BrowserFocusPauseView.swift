import SwiftUI

/// What a site shows once its daily limit is used: a calm pause over the
/// page, with five more minutes or the tab's close.
struct BrowserFocusPauseView: View {
    let site: String
    let limit: SiteTimeLimit
    let extend: () -> Void
    let closeTab: () -> Void

    var body: some View {
        VStack(spacing: OdeSpacing.medium) {
            Image(systemName: "moon.circle")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("\(site) is paused")
                .font(.title2.weight(.semibold))
            Text("You set \(Self.duration(limit.minutesPerDay)) a day here. It opens again tomorrow.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: OdeSpacing.small) {
                Button("Close Tab", action: closeTab)
                    .accessibilityIdentifier("focus-pause-close-tab")
                Button("Five More Minutes", action: extend)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("focus-pause-five-more-minutes")
            }
            .controlSize(.large)
            .padding(.top, OdeSpacing.small)
        }
        .padding(OdeSpacing.extraExtraLarge)
        .frame(maxWidth: 420)
        .background {
            OdeSurfaceLayer(shape: .rect(cornerRadius: OdeCornerScale.surface, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The page stays out of sight behind the pause.
        .background { Rectangle().fill(.background) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(site) is paused")
    }

    /// The limit as a person says it: minutes, hours, or both.
    static func duration(_ minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .full
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
    }
}
