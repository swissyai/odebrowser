import SwiftUI

/// Under the version on About: where software updates stand, in a line,
/// and the engine version pages run in.
struct BrowserPlatformAboutStatus: View {
    // MARK: - Variables

    @Environment(BrowserSoftwareUpdateService.self) private var softwareUpdates
    @Environment(\.browserMacWindows) private var windows

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.extraExtraSmall) {
            Label {
                Text(updateState)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(OdeBrandTheme.accentText)
                    .accessibilityHidden(true)
            }
            if let engine = windows?.engineCredits {
                Text(verbatim: engine)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var model: BrowserSoftwareUpdateModel { softwareUpdates.model }

    /// The update under way, by its phase and version, or whether Ode
    /// looks for one by itself.
    private var updateState: String {
        guard softwareUpdates.isEnabled else { return String(localized: "Updates are off in this build") }
        guard model.phase == .idle else {
            if model.phase.isTitledByUpdate, let title = model.updateTitle {
                return String(localized: "\(title) is available")
            }
            if let version = model.updateVersion {
                return String(localized: "\(String(localized: model.phase.title)), version \(version)")
            }
            return String(localized: model.phase.title)
        }
        return softwareUpdates.automaticallyChecksForUpdates
            ? String(localized: "Ode checks for updates automatically")
            : String(localized: "Automatic update checks are off")
    }

    private var symbol: String {
        guard softwareUpdates.isEnabled, softwareUpdates.automaticallyChecksForUpdates || model.phase != .idle else {
            return "pause.circle"
        }
        return model.phase == .idle ? "checkmark.circle" : "arrow.down.circle"
    }
}
