import SwiftUI

/// Where an update under way stands, as a row of the software update settings:
/// the same state the sidebar card shows, which stays here when the card is
/// hidden.
struct BrowserSoftwareUpdateStatusRow: View {
    // MARK: - Variables

    let model: BrowserSoftwareUpdateModel

    @Environment(\.browserSoftwareUpdateDetails) private var showDetails

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
            HStack(alignment: .firstTextBaseline, spacing: OdeSpacing.small) {
                VStack(alignment: .leading, spacing: OdeSpacing.extraExtraSmall) {
                    title
                    if let versionLine {
                        Text(verbatim: versionLine)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: OdeSpacing.small)
                if hasDetails, let showDetails {
                    Button("What's new") { showDetails() }
                        .buttonStyle(.link)
                        .accessibilityLabel("Review update details")
                }
            }

            if let message = model.message {
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let progress = model.progress, model.phase.isTransferring {
                BrowserSoftwareUpdateProgress(progress: progress)
            } else if model.phase.isWorking {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Software update progress")
            }
        }
    }

    private var title: Text {
        if model.phase.isTitledByUpdate, let updateTitle = model.updateTitle {
            return Text(verbatim: updateTitle)
        }
        return Text(model.phase.title)
    }

    /// The update's version, unless the title already names it.
    private var versionLine: String? {
        guard !model.phase.isTitledByUpdate, let version = model.updateVersion else { return nil }
        return String(localized: "Version \(version)")
    }

    private var hasDetails: Bool {
        if let releaseNotes = model.releaseNotes, !releaseNotes.isEmpty { return true }
        return model.informationURL != nil
    }
}
