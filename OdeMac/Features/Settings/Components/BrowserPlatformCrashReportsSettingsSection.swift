import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The crash and hang reports Ode keeps on this Mac, with what happens to new
/// ones, and each report to read, copy, save, send or delete.
struct BrowserPlatformCrashReportsSettingsSection: View {
    @Environment(BrowserCrashReports.self) private var reports: BrowserCrashReports?
    @State private var viewing: BrowserCrashReport?

    var body: some View {
        if let reports {
            Section {
                Picker(
                    "When Ode has a report",
                    selection: Binding(get: { reports.sending }, set: { reports.sending = $0 })
                ) {
                    ForEach(BrowserCrashReports.Sending.allCases) { sending in
                        Text(sending.title).tag(sending)
                    }
                }
                .accessibilityIdentifier("settings-reports-sending")
                .settingsSearchTarget(.crashReports)
                if reports.reports.isEmpty {
                    Text("No reports. Ode keeps reports of crashes and hangs on this Mac for 30 days.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reports.reports) { report in
                        BrowserCrashReportRow(
                            report: report, canSend: reports.canSend,
                            view: { viewing = report },
                            send: { Task { await reports.send(report) } },
                            delete: { reports.delete(report) })
                    }
                }
            } header: {
                Text("Crash and hang reports")
            } footer: {
                Text(
                    reports.canSend
                        ? "Reports never include the pages you visit. Nothing leaves this Mac unless you send it."
                        : "Reports never include the pages you visit. Ode has no report server yet, so save or copy a report to share it."
                )
            }
            .sheet(item: $viewing) { report in
                BrowserCrashReportViewer(report: report) { viewing = nil }
            }
        }
    }
}

/// One report in the list.
private struct BrowserCrashReportRow: View {
    let report: BrowserCrashReport
    let canSend: Bool
    let view: () -> Void
    let send: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OdeSpacing.medium) {
            VStack(alignment: .leading, spacing: OdeSpacing.extraExtraSmall) {
                Text(report.title)
                Text("\(report.taken) · \(delivery)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(report.summary)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: OdeSpacing.medium)
            Button("View", action: view)
            Menu {
                Button("Copy report") { BrowserCrashReportActions.copy(report) }
                Button("Save report…") { BrowserCrashReportActions.save(report) }
                Button("Send", action: send)
                    .disabled(!canSend)
                Divider()
                Button("Delete", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More for this report")
        }
        .accessibilityElement(children: .contain)
    }

    private var delivery: String {
        switch report.delivery {
        case .notSent: String(localized: "Not sent")
        case .sent(let date): String(localized: "Sent \(date.formatted(date: .abbreviated, time: .shortened))")
        case .failed: String(localized: "Not sent: the last try failed")
        }
    }
}

/// A report as it would be sent.
private struct BrowserCrashReportViewer: View {
    let report: BrowserCrashReport
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.medium) {
            Text(report.title)
                .font(.title3.weight(.semibold))
            Text("This is everything the report holds.")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(BrowserCrashReportPayload.text(for: report))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OdeSpacing.medium)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: OdeCornerScale.control, style: .continuous))
            HStack {
                Button("Copy report") { BrowserCrashReportActions.copy(report) }
                Button("Save report…") { BrowserCrashReportActions.save(report) }
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 480)
    }
}

/// Copying and saving a report's text, the ways to share one without a server.
@MainActor
enum BrowserCrashReportActions {
    static func copy(_ report: BrowserCrashReport) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BrowserCrashReportPayload.text(for: report), forType: .string)
    }

    static func save(_ report: BrowserCrashReport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Ode report \(report.occurredAt.formatted(.iso8601.year().month().day())).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(BrowserCrashReportPayload.text(for: report).utf8).write(to: url, options: .atomic)
    }
}
