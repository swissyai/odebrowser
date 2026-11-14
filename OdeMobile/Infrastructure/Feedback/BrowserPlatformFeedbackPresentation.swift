import SwiftUI
import UIKit

@MainActor
final class BrowserPlatformFeedbackPresentation: NSObject {
    // MARK: - Static Variables

    private static var active: BrowserPlatformFeedbackPresentation?

    // MARK: - Variables

    private weak var window: UIWindow?
    private weak var parent: UIViewController?
    private let draft: BrowserFeedbackDraft
    private let allowsCapture: Bool
    private var form: UIViewController?
    private var isTransitioning = false

    // MARK: - Initializers

    private init(
        window: UIWindow, scene: UIWindowScene, parent: UIViewController,
        draft: BrowserFeedbackDraft, allowsCapture: Bool
    ) {
        self.window = window
        self.parent = parent
        self.draft = draft
        self.allowsCapture = allowsCapture
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(sourceSceneDisconnected), name: UIScene.didDisconnectNotification, object: scene)
    }

    // MARK: - Actions - Presentation

    static func present(draft: BrowserFeedbackDraft, allowsCapture: Bool = false, window: UIWindow? = nil) {
        guard active == nil, let window, let scene = window.windowScene,
            var parent = window.rootViewController
        else { return }
        while let presented = parent.presentedViewController { parent = presented }
        let owner = BrowserPlatformFeedbackPresentation(
            window: window, scene: scene, parent: parent, draft: draft, allowsCapture: allowsCapture)
        active = owner
        owner.capture(retake: false)
        owner.show()
    }

    private func show() {
        guard Self.active === self else { return }
        guard let parent, parent.view.window != nil else {
            end()
            return
        }
        let form = UIHostingController(
            rootView: BrowserFeedbackComposer(
                draft: draft, close: { [weak self] in self?.close() },
                retake: { [weak self] in self?.retake() }))
        self.form = form
        // Explicit Close keeps ownership deterministic; drafts never depend on controller lifetime.
        form.isModalInPresentation = true
        isTransitioning = true
        parent.present(form, animated: true) { [weak self] in self?.isTransitioning = false }
    }

    private func close() {
        guard let form, !isTransitioning else { return }
        isTransitioning = true
        form.dismiss(animated: true) { [self] in
            guard Self.active === self else { return }
            end()
        }
    }

    private func retake() {
        guard let form, !isTransitioning else { return }
        isTransitioning = true
        form.view.endEditing(true)
        form.dismiss(animated: true) { [self] in
            guard Self.active === self else { return }
            self.form = nil
            capture(retake: true)
            show()
        }
    }

    @objc private func sourceSceneDisconnected() {
        end()
    }

    private func end() {
        guard Self.active === self else { return }
        NotificationCenter.default.removeObserver(self)
        let closingForm = form
        form = nil
        parent = nil
        window = nil
        Self.active = nil
        closingForm?.dismiss(animated: false)
    }

    // MARK: - Actions - Capture

    private func capture(retake: Bool) {
        guard let id = draft.beginCapture(retake: retake) else { return }
        guard allowsCapture, let window, !window.isHidden else {
            draft.finishCapture(
                id, png: nil,
                message: String(
                    localized:
                        "Screenshot unavailable for this window. Automatic screenshots are off in private browsing."))
            return
        }
        window.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        var succeeded = false
        let image = renderer.image { _ in
            succeeded = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let png = succeeded ? image.pngData() : nil
        draft.finishCapture(
            id, png: png,
            message: png == nil
                ? String(localized: "Couldn’t prepare the screenshot. Your report is kept; try Retake.") : nil)
    }
}

/// Reads the actual source window, never an arbitrary connected scene.
struct BrowserPlatformFeedbackSource: UIViewRepresentable {
    @Binding var action: ((BrowserFeedbackDraft, Bool) -> Void)?

    func makeUIView(context: Context) -> SourceView { SourceView() }

    func updateUIView(_ view: SourceView, context: Context) {
        view.install = { window in
            action = { [weak window] draft, allowed in
                BrowserPlatformFeedbackPresentation.present(draft: draft, allowsCapture: allowed, window: window)
            }
        }
        view.installIfNeeded()
    }

    final class SourceView: UIView {
        var install: ((UIWindow) -> Void)?
        private weak var installedWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installIfNeeded()
        }

        func installIfNeeded() {
            guard let window, installedWindow !== window else { return }
            installedWindow = window
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                install?(window)
            }
        }
    }
}
