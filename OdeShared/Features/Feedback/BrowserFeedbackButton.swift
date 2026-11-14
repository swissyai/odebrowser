import SwiftUI

extension EnvironmentValues {
    @Entry var browserFeedbackCaptureAllowed = false
}

/// The draft outlives the native presentation and its source settings surface.
struct BrowserFeedbackButton: View {
    // MARK: - Variables

    let title: LocalizedStringResource
    let systemImage: String
    var topic: String? = nil
    var draft: BrowserFeedbackDraft = .shared
    @Environment(\.browserFeedbackCaptureAllowed) private var allowsCapture
    @State private var present: ((BrowserFeedbackDraft, Bool) -> Void)?

    var body: some View {
        Button {
            draft.prepare(topic: topic)
            present?(draft, allowsCapture)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.odeTertiary)
        .background { BrowserPlatformFeedbackSource(action: $present).frame(width: 0, height: 0) }
    }
}
