import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct BrowserFeedbackComposer: View {
    // MARK: - Types

    private enum Field: Hashable {
        case topic
        case report
    }

    private struct ScreenshotDocument: FileDocument {
        static let readableContentTypes = [UTType.png]
        let data: Data

        init(data: Data) { self.data = data }

        init(configuration: ReadConfiguration) throws {
            guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            self.data = data
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }

    // MARK: - Variables

    @Bindable var draft: BrowserFeedbackDraft
    var close: (() -> Void)? = nil
    var retake: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var screenshotToSave: ScreenshotDocument?
    @State private var isSavingScreenshot = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: OdeSpacing.extraExtraLarge) {
                    reportFields
                    screenshotSection
                    detailsSection
                    aboutFeedback
                }
                .padding(OdeSpacing.extraExtraLarge)
            }
            .scrollDismissesKeyboard(.interactively)
            footer.layoutPriority(1)
        }
        .background(OdeBrandTheme.canvas)
        .foregroundStyle(OdeBrandTheme.textDisplay)
        .tint(OdeBrandTheme.accent)
        .odeFieldSurfaceRole(.brand)
        #if os(macOS)
            .frame(minWidth: 440, idealWidth: 520, minHeight: 540, idealHeight: 700)
        #endif
        .onAppear { focusedField = .report }
        .fileExporter(
            isPresented: $isSavingScreenshot, document: screenshotToSave,
            contentType: .png, defaultFilename: "Ode-window"
        ) { result in
            screenshotToSave = nil
            switch result {
            case .success:
                draft.screenshotSaveFinished(succeeded: true)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    draft.screenshotSaveFinished(succeeded: false)
                }
            }
        }
        .onChange(of: draft.status) {
            if let status = draft.status {
                AccessibilityNotification.Announcement(status.message).post()
            }
        }
    }

    // MARK: - Actions - Presentation

    private var header: some View {
        HStack(spacing: OdeSpacing.medium) {
            OdeMark().frame(width: 26, height: 26).accessibilityHidden(true)
            Text("Feedback")
                .font(OdeTypography.displayPage)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Close", systemImage: "xmark") {
                focusedField = nil
                if let close { close() } else { dismiss() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(OdeChromeButtonStyle())
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, OdeSpacing.extraExtraLarge)
        .padding(.vertical, OdeSpacing.large)
        .background(OdeBrandTheme.surface)
    }

    private var reportFields: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.medium) {
            TextField("Topic (optional)", text: $draft.topic)
                .focused($focusedField, equals: .topic)
                .odeTextField()
                .accessibilityIdentifier("feedback-topic")
            Text("Report")
                .font(OdeTypography.controlTitle)
            TextEditor(text: $draft.report)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.vertical, OdeSpacing.small)
                .frame(minHeight: 140)
                .focused($focusedField, equals: .report)
                .odeFieldSurface(isFocused: focusedField == .report)
                .accessibilityLabel("Report")
                .accessibilityIdentifier("feedback-report")
        }
        .font(.body)
    }

    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.medium) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OdeSpacing.medium) {
                    screenshotHeading
                    Spacer()
                    screenshotActions
                }
                VStack(alignment: .leading, spacing: OdeSpacing.medium) {
                    screenshotHeading
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: OdeSpacing.medium) { screenshotActions }
                        VStack(alignment: .leading, spacing: OdeSpacing.small) { screenshotActions }
                    }
                }
            }
            if let data = draft.screenshot,
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            {
                Image(image, scale: 1, label: Text("Screenshot attached to this report"))
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    .clipShape(.rect(cornerRadius: OdeRadius.card))
                Text("Review the screenshot for private information before sharing.")
                    .font(.callout)
                    .foregroundStyle(OdeBrandTheme.textSecondary)
            }
            if let message = draft.captureMessage {
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(OdeBrandTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var screenshotHeading: some View {
        Text("Screenshot")
            .font(OdeTypography.displaySection)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var screenshotActions: some View {
        if draft.screenshot != nil {
            Button("Save", systemImage: "square.and.arrow.down") {
                if let data = draft.screenshot {
                    screenshotToSave = ScreenshotDocument(data: data)
                    isSavingScreenshot = true
                }
            }
            .buttonStyle(.odeSecondary)
            .disabled(draft.isSending)
            .accessibilityLabel("Save Screenshot")
            Button("Remove", systemImage: "trash") { draft.removeScreenshot() }
                .buttonStyle(.odeSecondary)
                .disabled(draft.isSending)
        }
        if let retake {
            Button("Retake", systemImage: "camera") {
                focusedField = nil
                retake()
            }
            .buttonStyle(.odeSecondary)
            .disabled(draft.isCapturing || draft.isSending)
            .accessibilityHint("Captures only this Ode window.")
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.medium) {
            Toggle("Include version, build, and OS", isOn: $draft.includesAppDetails)
                .font(OdeTypography.controlTitle)
                .accessibilityIdentifier("feedback-include-details")
            DisclosureGroup("App details") {
                Text(verbatim: draft.appDetails)
                    .font(.callout.monospacedDigit())
                    .textSelection(.enabled)
                Text("Version, build, and OS only. No logs or browsing history.")
                    .font(.callout)
                    .foregroundStyle(OdeBrandTheme.textSecondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.medium) {
            submissionDisclosure
                .font(.callout)
                .foregroundStyle(OdeBrandTheme.textSecondary)
            if let status = draft.status {
                Text(verbatim: status.message)
                    .font(.callout)
                    .foregroundStyle(OdeBrandTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("feedback-status")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OdeSpacing.medium) { handoffButtons }
                VStack(alignment: .leading, spacing: OdeSpacing.medium) { handoffButtons }
            }
        }
        .padding(.horizontal, OdeSpacing.extraExtraLarge)
        .padding(.vertical, OdeSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OdeBrandTheme.surface)
        .overlay(alignment: .top) { Divider() }
    }

    private var aboutFeedback: some View {
        DisclosureGroup("About feedback") {
            Text("Unsent drafts stay in Ode until you quit.")
            Text("Copy Text includes the recipient and full report text.")
            Text("Email links include text only. Save the screenshot to attach it.")
            Button("Open Email Link", systemImage: "envelope") {
                focusedField = nil
                draft.openEmail(using: BrowserPlatformFeedbackHandoff.open)
            }
            .buttonStyle(.odeSecondary)
            .disabled(!draft.hasReport || draft.isOpeningEmail || draft.isSending)
        }
        .font(.callout)
    }

    @ViewBuilder
    private var submissionDisclosure: some View {
        if draft.screenshot != nil {
            if draft.includesAppDetails {
                Text("Your report, screenshot, and app details go to Ode.")
            } else {
                Text("Your report and screenshot go to Ode.")
            }
        } else if draft.includesAppDetails {
            Text("Your report and app details go to Ode.")
        } else {
            Text("Your report goes to Ode.")
        }
    }

    @ViewBuilder
    private var handoffButtons: some View {
        Button {
            focusedField = nil
            Task { await draft.send(using: BrowserFeedbackClient.shared.send) }
        } label: {
            if draft.canRetrySending {
                Label("Retry", systemImage: "arrow.clockwise")
            } else {
                Label("Send to Ode", systemImage: "paperplane")
            }
        }
        .buttonStyle(.odePrimary)
        .disabled(!draft.hasReport || draft.isSending)
        .accessibilityIdentifier("feedback-send")

        Button("Copy Text", systemImage: "doc.on.doc") {
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
