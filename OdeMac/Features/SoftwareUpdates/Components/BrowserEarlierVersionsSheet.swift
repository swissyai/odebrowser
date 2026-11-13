import SwiftUI

/// Going back to an earlier version: the versions the update feed still
/// lists, then the chosen one downloaded and checked, with anything it
/// cannot keep from this version, before Ode restarts into it.
struct BrowserEarlierVersionsSheet: View {
    // MARK: - Variables

    let rollback: BrowserSoftwareUpdateRollback
    let close: () -> Void

    @State private var selection: BrowserSoftwareUpdateRelease.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.medium) {
            Text("Go back to an earlier version")
                .font(.title3.weight(.semibold))
            Text(
                "Your Spaces, tabs and settings stay as they are. Ode offers the newest version again once a newer one is out."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            content
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            if let failure = rollback.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            if rollback.releases.isEmpty, rollback.plan == nil { rollback.loadReleases() }
            selection = selection ?? rollback.releases.first?.id
        }
        .onChange(of: rollback.releases) { _, releases in
            selection = releases.first?.id
        }
    }

    // MARK: - Actions - Layout

    @ViewBuilder
    private var content: some View {
        if let plan = rollback.plan {
            VStack(alignment: .leading, spacing: OdeSpacing.small) {
                Label("Ode \(plan.release.version) is ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.primary)
                ForEach(plan.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Ode quits, puts Ode \(plan.release.version) in its place and opens again.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let activity = rollback.activity {
            VStack(alignment: .leading, spacing: OdeSpacing.small) {
                Text(activity)
                if let progress = rollback.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        } else if rollback.isLoading {
            HStack(spacing: OdeSpacing.small) {
                ProgressView().controlSize(.small)
                Text("Reading the update feed…").foregroundStyle(.secondary)
            }
        } else if rollback.releases.isEmpty {
            if rollback.failure == nil {
                Text("The update feed lists no earlier version this Mac can run.")
                    .foregroundStyle(.secondary)
            }
        } else {
            List(rollback.releases, selection: $selection) { release in
                HStack {
                    Text("Ode \(release.version)")
                    Spacer()
                    if let published = release.publishedAt {
                        Text(published.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                    Text(ByteCountFormatter.string(fromByteCount: release.length, countStyle: .file))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .tag(release.id)
            }
            .listStyle(.bordered)
            .frame(height: 180)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                rollback.cancel()
                close()
            }
            .keyboardShortcut(.cancelAction)
            if let plan = rollback.plan {
                Button("Go back to Ode \(plan.release.version)") { rollback.goBack() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Download") {
                    guard let release = rollback.releases.first(where: { $0.id == selection }) else { return }
                    rollback.prepare(release)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil || rollback.activity != nil)
            }
        }
    }
}
