import SwiftUI

/// The dated copies of the session, newest first: when each was taken, why,
/// and how many Spaces and tabs it held, with the button that restores the
/// one chosen.
struct BrowserRestoreCopiesView: View {
    let model: BrowserRestoreCopiesModel
    let cancel: @MainActor () -> Void

    @State private var selection: RecoveryCopy.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.large) {
            Text("Restore from an earlier copy")
                .font(.title2.bold())
            Text(model.explanation)
                .fixedSize(horizontal: false, vertical: true)
            if model.copies.isEmpty {
                Text("There are no earlier copies yet. Ode keeps one each time it starts.")
                    .foregroundStyle(.secondary)
            } else {
                List(model.copies, selection: $selection) { copy in
                    BrowserRestoreCopyRow(copy: copy)
                        .tag(copy.id)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(height: 240)
                // A rounded box like the window's other surfaces, not the
                // bordered list's square one.
                .clipShape(.rect(cornerRadius: OdeCornerScale.row))
                .overlay {
                    RoundedRectangle(cornerRadius: OdeCornerScale.row).strokeBorder(.separator, lineWidth: 0.5)
                }
                .accessibilityIdentifier("restore-copies-list")
            }
            if let failure = model.failure {
                Text(failure)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: OdeSpacing.medium) {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(model.timing == .relaunch ? "Restore and reopen" : "Restore") {
                    if let copy = selected { model.restore(copy) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil)
                .accessibilityIdentifier("restore-copies-restore")
            }
        }
        .padding(28)
        .frame(width: 540, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { selection = selection ?? model.initialSelection }
    }

    private var selected: RecoveryCopy? {
        model.copies.first { $0.id == selection }
    }
}

/// One copy in the restore list.
struct BrowserRestoreCopyRow: View {
    let copy: RecoveryCopy

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.extraExtraSmall) {
            HStack(alignment: .firstTextBaseline, spacing: OdeSpacing.medium) {
                Text(copy.taken)
                    .fontWeight(.medium)
                Spacer(minLength: OdeSpacing.small)
                Text(copy.contents)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Label(copy.reason, systemImage: copy.held ? "exclamationmark.triangle" : "clock.arrow.circlepath")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, OdeSpacing.extraSmall)
        .accessibilityElement(children: .combine)
    }
}
