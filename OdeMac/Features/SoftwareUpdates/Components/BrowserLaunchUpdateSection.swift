import SwiftUI

/// Where a launch that cannot open the browser looks for and installs a newer
/// version, from the safe start or recovery window: where the update stands
/// and what it offers next, with no browser window running. Skipping a version
/// is left to the sidebar card; a launch that failed never offers it.
struct BrowserLaunchUpdateSection: View {
    // MARK: - Types

    enum Purpose {
        /// The last launches did not finish starting.
        case failedStarts
        /// The session could not be opened.
        case session
    }

    // MARK: - Variables

    let softwareUpdates: BrowserSoftwareUpdateService
    let purpose: Purpose

    var body: some View {
        let model = softwareUpdates.model
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: OdeSpacing.small) {
            switch model.phase {
            case .idle, .unavailable:
                Button(purpose == .failedStarts ? "Check for a fixed version" : "Check for updates") {
                    softwareUpdates.checkForUpdates()
                }
                .disabled(!softwareUpdates.isEnabled)
                .accessibilityIdentifier("launch-update-check")
                if !softwareUpdates.isEnabled {
                    Text("Updates can't be checked in this copy of Ode.")
                        .foregroundStyle(.secondary)
                }
            case .checking:
                HStack(spacing: OdeSpacing.small) {
                    ProgressView().controlSize(.small)
                    Text(purpose == .failedStarts ? "Checking for a fixed version…" : "Checking for updates…")
                }
            case .upToDate:
                Text("No newer version yet.")
            case .available:
                Text("Version \(snapshot.version ?? "") is available")
                    .font(.headline)
                if purpose == .failedStarts {
                    Text("It may fix the problem that stopped Ode from starting.")
                }
            default:
                Text(model.phase.title)
                    .font(.headline)
                if let message = snapshot.message, model.phase.showsMessage {
                    Text(message)
                }
                if let progress = snapshot.progress, model.phase.isTransferring {
                    ProgressView(value: progress)
                }
            }
            if let buttons = model.phase.windowButtons(for: snapshot) {
                HStack(spacing: OdeSpacing.small) {
                    ForEach(Array(offered(buttons).enumerated()), id: \.offset) { _, button in
                        Button(String(localized: button.title)) { button.action.perform(on: model) }
                            .buttonStyle(.bordered)
                            .tint(button.isProminent ? .accentColor : nil)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The window's buttons for the update, without skipping it.
    private func offered(_ buttons: BrowserSoftwareUpdatePhase.WindowButtons) -> [BrowserSoftwareUpdatePhase.WindowButton] {
        (buttons.leading + buttons.trailing).filter { $0.action != .dismissExactUpdate }
    }
}
