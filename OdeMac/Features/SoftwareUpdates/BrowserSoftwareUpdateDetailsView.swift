import SwiftUI

/// Full release notes for an update the sidebar is already presenting.
///
/// This window is deliberately passive: closing it never changes Sparkle's
/// pending choice, and only the sidebar's explicit What's New control opens it.
struct BrowserSoftwareUpdateDetailsView: View {
    // MARK: - Variables

    let model: BrowserSoftwareUpdateModel
    /// Closes the window showing this view, once the update it described is
    /// gone.
    let closeWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.large) {
            BrowserSoftwareUpdateStatusHeader(model: model)

            VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
                if let version = model.updateVersion {
                    Text("Version \(version)")
                }
                if let build = model.updateBuild, build != model.updateVersion {
                    Text("Build \(build)")
                }
                if model.isSecurityOnly {
                    Text("Security fixes only. Restart when it suits you.")
                }
            }
            .font(OdeTypography.metadata)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            if let progress = model.progress {
                BrowserSoftwareUpdateProgress(progress: progress)
            } else if model.phase.windowShowsActivity {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Software update progress")
            }

            if let releaseNotes = model.releaseNotes, !releaseNotes.isEmpty {
                BrowserSoftwareUpdateReleaseNotes(releaseNotes: releaseNotes)
            } else if !model.highlights.isEmpty {
                BrowserSoftwareUpdateReleaseNotes(
                    releaseNotes: model.highlights.map { "- \($0)" }.joined(separator: "\n"))
            } else if let informationURL = model.informationURL {
                Link("View the full release notes", destination: informationURL)
            }

            Spacer(minLength: 0)

            BrowserSoftwareUpdateActions(model: model)
        }
        .padding(OdeSpacing.extraLarge)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 260, idealHeight: 440)
        .background(OdeBrandTheme.canvas)
        .onChange(of: model.phase, initial: true) { _, phase in
            guard phase == .idle else { return }
            closeWindow()
        }
    }
}

/// Gives the sidebar's update card the window that shows full release notes.
struct BrowserSoftwareUpdateDetailsPresentation: ViewModifier {
    // MARK: - Variables

    let softwareUpdates: BrowserSoftwareUpdateService
    @Environment(\.browserMacWindows) private var windows

    private var automaticUpdates: Binding<Bool>? {
        guard softwareUpdates.isEnabled || softwareUpdates.model.isFixture else { return nil }
        return Binding(
            get: { softwareUpdates.automaticUpdatesEnabled },
            set: { softwareUpdates.setAutomaticUpdates($0) }
        )
    }

    func body(content: Content) -> some View {
        content.environment(
            \.browserSoftwareUpdateDetails,
            windows.map { windows in
                BrowserSoftwareUpdateDetailsAction(owner: windows) { [weak windows] in
                    windows?.openSoftwareUpdateDetails()
                }
            }
        )
        .environment(\.browserAutomaticUpdates, automaticUpdates)
    }
}

#Preview("Update Details") {
    let model = BrowserSoftwareUpdateModel()
    BrowserSoftwareUpdateDetailsView(model: model, closeWindow: {})
        .task {
            model.presentUpdate(
                title: "Ode 0.5.99",
                version: "0.5.99",
                releaseNotes: """
                    ## Highlights

                    ### Improved

                    - Software updates now stay in the sidebar.

                    ### Fixed

                    - Update details open only when requested.
                    """,
                isInformationOnly: false,
                install: {},
                skip: {}
            )
        }
}
