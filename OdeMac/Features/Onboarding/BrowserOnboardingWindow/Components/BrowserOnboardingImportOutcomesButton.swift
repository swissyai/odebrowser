import SwiftUI

/// Reopens device-local receipts without rereading any browser or requesting
/// Keychain access. Native rendering and actions are reviewed in the app.
struct BrowserOnboardingImportOutcomesButton: View {
    // MARK: - Variables

    let flow: BrowserOnboardingFlow
    @State private var isPresented = false

    var body: some View {
        if !flow.importOutcomes.isEmpty || flow.outcomeReadFailure != nil {
            Button("Import Results") {
                flow.reloadImportOutcomes()
                isPresented = true
            }
            .buttonStyle(.odeSecondary)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Import Results").font(.headline)
                        Spacer()
                        Button("Refresh", action: flow.reloadImportOutcomes)
                            .odeControlPointer()
                    }
                    if let failure = flow.outcomeReadFailure {
                        Text(failure).foregroundStyle(SpaceRoleStyle.dangerText)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(flow.importOutcomes.reversed()), id: \.id) { outcome in
                                receipt(outcome)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
                .frame(width: 560, height: 440)
            }
        }
    }

    // MARK: - Actions - Receipts

    private func receipt(_ outcome: SetupImportOutcome) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(outcome.sourceTitle).font(.headline)
            status(outcome)
            if outcome.status == .imported {
                Text(
                    "\(outcome.tabCount) tabs from \(outcome.spaceCount) source Spaces; \(outcome.passwordCount) passwords imported."
                )
                if outcome.passwordSkippedCount > 0 {
                    Text("\(outcome.passwordSkippedCount) passwords weren't imported. Existing passwords were kept.")
                }
                if outcome.cookieCount > 0 || outcome.expiredCookieCount > 0 || outcome.droppedCookieCount > 0 {
                    Text(
                        "\(outcome.cookieCount) cookies copied; \(outcome.expiredCookieCount) expired and \(outcome.droppedCookieCount) unreadable cookies left out. Sites may still require sign-in."
                    )
                }
                let extensions = Dictionary(grouping: outcome.extensions, by: \.extensionID)
                ForEach(extensions.keys.sorted(), id: \.self) { id in
                    if let items = extensions[id], let first = items.first {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(first.name).fontWeight(.medium)
                            Text(
                                "\(items.count { $0.status == .pending }) pending, \(items.count { $0.status == .installed }) installed, \(items.count { $0.status == .failed }) failed, \(items.count { $0.status == .removed }) removed destinations"
                            )
                        }
                    }
                }
                if outcome.extensions.contains(where: { $0.status == .pending }) {
                    Text(
                        "Pending extensions wait for their Spaces to be unlocked and a browser window to be available. Refresh to check their results."
                    )
                }
                if outcome.extensions.contains(where: { $0.status == .failed }) {
                    Text("Some extension installs failed. Check Extensions before retrying.")
                }
                if outcome.extensions.contains(where: { $0.status == .removed }) {
                    Text("Some destination Spaces were removed before installation.")
                }
            }
            ForEach(Array(Set(outcome.omissions)).sorted(), id: \.self) { omission in
                Text(omission).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func status(_ outcome: SetupImportOutcome) -> some View {
        switch outcome.status {
        case .started:
            Text(
                "Interrupted or still in progress. Check your Spaces before retrying; some data may already have been applied."
            )
        case .imported:
            if !outcome.omissions.isEmpty || outcome.passwordSkippedCount > 0 || outcome.signInSpacesSkipped > 0
                || outcome.expiredCookieCount > 0 || outcome.droppedCookieCount > 0
                || outcome.extensions.contains(where: { $0.status == .failed || $0.status == .removed })
            {
                Text("Imported with items left out or unconfirmed.")
            } else if outcome.extensions.contains(where: { $0.status == .pending }) {
                Text("Imported. Extensions are still pending.")
            } else {
                Text("Reviewed data imported.")
            }
        case .failed:
            Text("Import didn't complete. Check your Spaces before retrying.")
        case .cancelled:
            Text("Cancelled before applying.")
        }
    }

}
