import SwiftUI
import UIKit

struct MobileRegularDownloadFeedbackLayer: View {
    // MARK: - Variables

    let triggerFrameInGlobal: CGRect?
    let sidebarIsPresented: Bool
    let downloadCenter: BrowserDownloadCenter
    let profileID: UUID?
    let spaceID: UUID?

    var body: some View {
        if let triggerFrameInGlobal, sidebarIsPresented {
            BrowserDownloadFeedbackLayer(
                events: downloadCenter.feedbackEvents,
                profileID: profileID,
                spaceID: spaceID,
                destinationFrameInGlobal: triggerFrameInGlobal
            )
            .zIndex(MobileBrowserRootLayout.utilityLayer + 1)
        }
    }
}

struct BrowserDownloadFeedbackWindowIdentityReader: UIViewRepresentable {
    @Binding var identifier: ObjectIdentifier?

    func makeCoordinator() -> Coordinator {
        Coordinator(identifier: $identifier)
    }

    func makeUIView(context: Context) -> WindowIdentityView {
        let view = WindowIdentityView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.set(window.map(ObjectIdentifier.init))
        }
        return view
    }

    func updateUIView(_ uiView: WindowIdentityView, context: Context) {
        context.coordinator.identifier = $identifier
    }

    final class Coordinator {
        var identifier: Binding<ObjectIdentifier?>

        init(identifier: Binding<ObjectIdentifier?>) {
            self.identifier = identifier
        }

        func set(_ value: ObjectIdentifier?) {
            guard identifier.wrappedValue != value else { return }
            identifier.wrappedValue = value
        }
    }

    final class WindowIdentityView: UIView {
        var windowDidChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowDidChange?(window)
        }
    }
}
