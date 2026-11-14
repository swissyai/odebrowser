import AppKit
import ScreenCaptureKit
import SwiftUI

/// One explicit feedback sheet, bound to the window that requested it, including during retakes.
@MainActor
final class BrowserPlatformFeedbackPresentation: NSObject {
    // MARK: - Static Variables

    private static var active: BrowserPlatformFeedbackPresentation?

    // MARK: - Variables

    private weak var window: NSWindow?
    private let draft: BrowserFeedbackDraft
    private let allowsCapture: Bool
    private var panel: NSPanel?
    private var captureTask: Task<Void, Never>?
    private var captureID: UUID?
    private var isRetaking = false

    // MARK: - Initializers

    private init(window: NSWindow, draft: BrowserFeedbackDraft, allowsCapture: Bool) {
        self.window = window
        self.draft = draft
        self.allowsCapture = allowsCapture
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(sourceWindowClosed), name: NSWindow.willCloseNotification, object: window)
    }

    // MARK: - Actions - Presentation

    static func present(draft: BrowserFeedbackDraft, allowsCapture: Bool = false, window: NSWindow) {
        guard active == nil, window.isVisible else { return }
        let owner = BrowserPlatformFeedbackPresentation(window: window, draft: draft, allowsCapture: allowsCapture)
        active = owner
        owner.captureTask = Task { @MainActor in
            // Let a Command Bar's dismissal finish before sampling its source window.
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await owner.capture(retake: false)
            guard !Task.isCancelled else { return }
            owner.captureTask = nil
            owner.show()
        }
    }

    private func show() {
        guard Self.active === self else { return }
        guard let window, window.isVisible else {
            end()
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = String(localized: "Feedback")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentViewController = NSHostingController(
            rootView: BrowserFeedbackComposer(
                draft: draft, close: { [weak self] in self?.close() },
                retake: { [weak self] in self?.retake() }))
        self.panel = panel
        window.beginSheet(panel) { [weak self] _ in
            panel.orderOut(nil)
            guard let self, Self.active === self else { return }
            self.panel = nil
            if isRetaking {
                isRetaking = false
                captureTask = Task { @MainActor in
                    await capture(retake: true)
                    guard !Task.isCancelled else { return }
                    captureTask = nil
                    show()
                }
            } else {
                end()
            }
        }
    }

    private func close() {
        guard let panel, let window else { return }
        window.endSheet(panel)
    }

    private func retake() {
        guard let panel, let window, !draft.isCapturing, !isRetaking else { return }
        // beginSheet's completion waits for the native dismissal before capturing.
        isRetaking = true
        window.endSheet(panel)
    }

    @objc private func sourceWindowClosed() {
        end()
    }

    private func end() {
        guard Self.active === self else { return }
        captureTask?.cancel()
        captureTask = nil
        if let captureID { draft.cancelCapture(captureID) }
        captureID = nil
        NotificationCenter.default.removeObserver(self)
        let closingPanel = panel
        panel = nil
        Self.active = nil
        if let closingPanel {
            window?.endSheet(closingPanel)
            closingPanel.orderOut(nil)
        }
    }

    // MARK: - Actions - Capture

    private func capture(retake: Bool) async {
        guard Self.active === self, !Task.isCancelled,
            let id = draft.beginCapture(retake: retake)
        else { return }
        captureID = id
        defer {
            draft.cancelCapture(id)
            captureID = nil
        }
        guard allowsCapture else {
            draft.finishCapture(
                id, png: nil,
                message: String(
                    localized: "Automatic screenshots are off in private browsing or when window privacy is unknown."))
            return
        }
        guard let window, window.isVisible, window.attachedSheet == nil else {
            draft.finishCapture(
                id, png: nil,
                message: String(
                    localized: "Screenshot unavailable while another sheet is open. You can still write your report."))
            return
        }
        do {
            // Unlike global shareable-content enumeration, this API exposes only content
            // available to this process without TCC consent. Never request desktop access.
            let content = try await SCShareableContent.currentProcess
            guard !Task.isCancelled, Self.active === self, window.isVisible else { return }
            guard
                let source = content.windows.first(where: {
                    $0.windowID == CGWindowID(window.windowNumber)
                        && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                })
            else {
                draft.finishCapture(
                    id, png: nil,
                    message: String(
                        localized: "This Ode window isn’t available for capture. Your report is kept; try Retake."))
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: source)
            let configuration = SCStreamConfiguration()
            let scale = window.backingScaleFactor
            configuration.width = max(1, Int(source.frame.width * scale))
            configuration.height = max(1, Int(source.frame.height * scale))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard !Task.isCancelled, Self.active === self, window.isVisible else { return }
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            draft.finishCapture(
                id, png: png,
                message: png == nil
                    ? String(localized: "Couldn’t prepare the screenshot. Your report is kept; try Retake.") : nil)
        } catch {
            guard !Task.isCancelled, Self.active === self else { return }
            // Do not expose system errors that can contain titles, paths or browsing information.
            draft.finishCapture(
                id, png: nil,
                message: String(
                    localized:
                        "macOS couldn’t capture this Ode window. No desktop access was requested. Your report is kept; try Retake."
                ))
        }
    }
}

/// A settings button captures its own window, not whichever window becomes key later.
struct BrowserPlatformFeedbackSource: NSViewRepresentable {
    @Binding var action: ((BrowserFeedbackDraft, Bool) -> Void)?

    func makeNSView(context: Context) -> SourceView { SourceView() }

    func updateNSView(_ view: SourceView, context: Context) {
        view.install = { window in
            action = { [weak window] draft, allowed in
                guard let window else { return }
                BrowserPlatformFeedbackPresentation.present(draft: draft, allowsCapture: allowed, window: window)
            }
        }
        view.installIfNeeded()
    }

    final class SourceView: NSView {
        var install: ((NSWindow) -> Void)?
        private weak var installedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
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
