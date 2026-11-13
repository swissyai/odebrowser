import SwiftUI

/// The presenting surface owns only its sheet, not the session draft or its parent's dismissal.
struct BrowserFeedbackButton: View {
    // MARK: - Variables

    let title: LocalizedStringResource
    let systemImage: String
    var topic: String? = nil
    var draft: BrowserFeedbackDraft = .shared
    @State private var isPresented = false

    var body: some View {
        Button {
            draft.prepare(topic: topic)
            isPresented = true
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.odeTertiary)
        .sheet(isPresented: $isPresented) {
            BrowserFeedbackComposer(draft: draft)
        }
    }
}
