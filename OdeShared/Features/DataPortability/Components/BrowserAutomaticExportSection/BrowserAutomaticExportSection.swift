import SwiftUI
import UniformTypeIdentifiers

/// The automatic export's settings: whether it runs, the folder it writes
/// to, an export on demand, and how the latest one went.
struct BrowserAutomaticExportSection: View {
    // MARK: - Variables

    let automaticExport: BrowserAutomaticExport
    var presentsSystemPanels = true
    @State private var isChoosingFolder = false

    private var isEnabled: Binding<Bool> {
        Binding(get: { automaticExport.isEnabled }, set: { automaticExport.setEnabled($0) })
    }

    // MARK: - Actions - Content

    var body: some View {
        Section {
            Toggle("Export automatically", isOn: isEnabled)
                .accessibilityIdentifier("automatic-export-enabled")
                .settingsSearchTarget(.automaticExport)
            LabeledContent("Folder") {
                HStack(spacing: 8) {
                    Text((automaticExport.folder.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(automaticExport.folder.path)
                    Button("Choose…") { isChoosingFolder = true }
                        .accessibilityIdentifier("automatic-export-choose-folder")
                }
            }
            HStack(spacing: 8) {
                Button("Export Now") {
                    Task { await automaticExport.exportNow() }
                }
                .disabled(automaticExport.isWriting || !automaticExport.lockedSpaces.isEmpty)
                .accessibilityIdentifier("automatic-export-now")
                if let reveal = BrowserPlatformAutomaticExport.reveal, let url = automaticExport.lastExportURL {
                    Button("Show in Finder") { reveal(url) }
                        .accessibilityIdentifier("automatic-export-show")
                }
            }
            status
        } header: {
            Text("Automatic export")
        } footer: {
            Text(
                "Ode writes your Spaces, tabs, bookmarks and history to your chosen folder every day, and again within an hour of a change to your Spaces, pinned tabs or folders. Other apps can read the files: JSON, HTML bookmarks and JSON Lines. The last 7 exports are kept. Passwords and cookies are never written."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("automatic-export-description")
        }
        .modifier(
            BrowserAutomaticExportFolderPanel(
                isPresented: $isChoosingFolder, presentsSystemPanels: presentsSystemPanels,
                choose: automaticExport.setFolder))
    }

    @ViewBuilder
    private var status: some View {
        Group {
            if automaticExport.isWriting {
                ProgressView("Exporting…")
                    .controlSize(.small)
            } else if let failure = automaticExport.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if !automaticExport.lockedSpaces.isEmpty {
                Text("Exports wait until every Space is unlocked.")
                    .foregroundStyle(.secondary)
            } else if let lastExportedAt = automaticExport.lastExportedAt {
                Text("Last exported \(lastExportedAt.formatted(date: .abbreviated, time: .shortened)).")
                    .foregroundStyle(.secondary)
            } else {
                Text("Not exported yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .accessibilityIdentifier("automatic-export-status")
    }

}

/// The folder panel, where the shell presents system panels.
private struct BrowserAutomaticExportFolderPanel: ViewModifier {
    // MARK: - Variables

    @Binding var isPresented: Bool
    let presentsSystemPanels: Bool
    let choose: @MainActor (URL) -> Void

    // MARK: - Actions - Content

    func body(content: Content) -> some View {
        if presentsSystemPanels {
            content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { choose(url) }
            }
        } else {
            content
        }
    }
}
