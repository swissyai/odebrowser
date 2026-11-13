import SwiftUI

/// Previews what Tidy proposes for the Space's open tabs: folders whose names
/// the person may change, each with its tabs, and the duplicate tabs found by
/// address, under the reason no folders came when the model could not help.
/// Nothing changes until the person chooses Apply.
struct BrowserTidyTodaySheet: View {
    let tidy: BrowserTidyToday
    let apply: (_ groups: [BrowserTidyToday.Group], _ duplicates: [BrowserTidyToday.Tab]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var proposal: BrowserTidyToday.Proposal?
    @State private var groups: [BrowserTidyToday.Group] = []
    @State private var closesDuplicates = true

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Tidy Open Tabs")
                .toolbar { toolbar }
        }
        #if os(macOS)
            .frame(minWidth: 400, minHeight: 360)
        #endif
        .task {
            let proposed = await tidy.propose()
            groups = proposed.groups
            proposal = proposed
        }
    }

    @ViewBuilder
    private var content: some View {
        if let proposal {
            if proposal.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Tidy", systemImage: "sparkles")
                } description: {
                    Text(proposal.reason ?? "")
                }
            } else {
                proposalForm(duplicates: proposal.duplicates, reason: proposal.reason)
            }
        } else {
            ProgressView("Grouping tabs…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func proposalForm(duplicates: [BrowserTidyToday.Tab], reason: String?) -> some View {
        Form {
            if let reason {
                Section {
                    Text(reason)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach($groups) { $group in
                Section {
                    TextField("Folder Name", text: $group.name)
                        .accessibilityIdentifier("tidy-folder-name")
                    ForEach(group.tabs) { tab in
                        Text(tab.title)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !duplicates.isEmpty {
                Section("Duplicates") {
                    Toggle("Close Duplicates", isOn: $closesDuplicates)
                    ForEach(duplicates) { tab in
                        Text(tab.title)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if proposal?.isEmpty == true {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply", action: applyProposal)
                    .disabled(proposal == nil)
                    .accessibilityIdentifier("apply-tidy")
            }
        }
    }

    /// Applies the folders under the names the person left, and the
    /// duplicates only while the switch is on. A cleared name leaves the
    /// folder to the core's default name.
    private func applyProposal() {
        let named = groups.map { group in
            var group = group
            group.name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return group
        }
        apply(named, closesDuplicates ? proposal?.duplicates ?? [] : [])
        dismiss()
    }
}
