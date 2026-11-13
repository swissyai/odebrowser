import SwiftUI

/// The share sheet's Ode entry: nothing while the link is handed to Ode,
/// or a short notice when it could not be.
struct OdeShareView: View {
    // MARK: - Variables

    let model: OdeShareModel

    var body: some View {
        if let notice = model.notice {
            NavigationStack {
                ContentUnavailableView {
                    Label {
                        Text(notice.title)
                    } icon: {
                        Image(systemName: notice.systemImage)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: model.close)
                    }
                }
            }
        } else {
            Color.clear
        }
    }
}
