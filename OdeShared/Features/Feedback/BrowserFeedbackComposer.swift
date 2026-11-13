import SwiftUI

struct BrowserFeedbackComposer: View {
    // MARK: - Types

    private enum Field: Hashable {
        case topic
        case report
    }

    // MARK: - Variables

    @Bindable var draft: BrowserFeedbackDraft
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                reportSection
                detailsSection
                handoffSection
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text("Feedback"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        focusedField = nil
                        dismiss()
                    }
                }
                #if os(iOS)
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focusedField = nil }
                    }
                #endif
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, idealWidth: 520, minHeight: 540, idealHeight: 620)
        #endif
        .onChange(of: draft.status) {
            if let status = draft.status {
                AccessibilityNotification.Announcement(status.message).post()
            }
        }
    }

    // MARK: - Actions - Presentation

    private var reportSection: some View {
        Section {
            TextField("Topic (optional)", text: $draft.topic)
                .focused($focusedField, equals: .topic)
                .accessibilityIdentifier("feedback-topic")
            TextEditor(text: $draft.report)
                .font(.body)
                .frame(minHeight: 140)
                .focused($focusedField, equals: .report)
                .accessibilityLabel("Report")
                .accessibilityIdentifier("feedback-report")
        } header: {
            Text("Report")
        }
    }

    private var detailsSection: some View {
        Section {
            Text(verbatim: draft.appDetails)
                .font(.callout.monospacedDigit())
                .textSelection(.enabled)
            Toggle("Include app details", isOn: $draft.includesAppDetails)
                .accessibilityIdentifier("feedback-include-details")
        }
    }

    private var handoffSection: some View {
        Section {
            LabeledContent("To") {
                Text(verbatim: BrowserFeedbackDraft.recipient)
                    .textSelection(.enabled)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OdeSpacing.medium) { handoffButtons }
                VStack(alignment: .leading, spacing: OdeSpacing.medium) { handoffButtons }
            }
            if let status = draft.status {
                Text(verbatim: status.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("feedback-status")
            }
            DisclosureGroup("About feedback") {
                Text("Avoid passwords and private information.")
                Text("Your draft stays in Ode until you quit.")
                Text(
                    "App details include only the version, build, and OS shown above. No browsing data or attachments."
                )
                Text("You choose the sender and send from your email app. Ode can’t confirm delivery.")
                Text("Copy Report includes the recipient and full report for webmail or long messages.")
            }
        }
    }

    @ViewBuilder
    private var handoffButtons: some View {
        Button("Open Email", systemImage: "envelope") {
            focusedField = nil
            draft.openEmail(using: BrowserPlatformFeedbackHandoff.open)
        }
        .buttonStyle(.odePrimary)
        .disabled(!draft.hasReport || draft.isOpeningEmail)
        .accessibilityIdentifier("feedback-open-email")

        Button("Copy Report", systemImage: "doc.on.doc") {
            focusedField = nil
            draft.copyReport(using: BrowserPlatformFeedbackHandoff.copy)
        }
        .buttonStyle(.odeSecondary)
        .disabled(!draft.hasReport)
        .accessibilityIdentifier("feedback-copy-report")
    }
}

#if DEBUG
    #Preview("Feedback") {
        BrowserFeedbackComposer(
            draft: BrowserFeedbackDraft(
                version: "1.0", build: "1",
                osVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
            )
        )
    }
#endif
