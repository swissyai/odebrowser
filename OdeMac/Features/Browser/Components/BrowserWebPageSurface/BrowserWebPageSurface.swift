import SwiftUI

struct BrowserWebPageSurface: View {
    let page: BrowserPage
    let browser: BrowserStore
    let pagePresentation: PagePresentation
    /// Whether the window's page commands act on this page: a Peek open over
    /// the active tab, or else the tab's own page. That page alone takes the
    /// keyboard, for its find bar and as focus returns to it, so the tab
    /// under an open Peek never takes it from the Peek.
    let isPageActive: Bool
    let focusRestorationGate: BrowserWebFocusRestorationGate
    /// Where the tab holding a page sits in its Space and what it is called,
    /// for lists that follow the sidebar.
    var tabPlacement: (UUID) -> BrowserShareSourceOffer.TabPlacement? = { _ in nil }
    /// Whether the page may offer the page of an id to share: one whose tab
    /// the page's own Space shows.
    var offersPage: (UUID) -> Bool = { _ in true }
    /// Shows the tab at the other end of the page's tab sharing, when Ode
    /// knows it; the sharing bars lead there.
    var goToSharingCounterpart: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The agent using the page's tab now, when one does.
    private var agent: AgentSessionState? {
        guard let tabID = browser.core.state.pages[page.corePage.id]?.tabID else { return nil }
        return browser.core.state.agentSessions.first { $0.tabIDs.contains(tabID) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            BrowserPlatformWebView(
                page: page,
                isPageActive: isPageActive,
                focusRestorationGate: focusRestorationGate
            )
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .global)
            } action: { _ in
                (page.nativeView as? any BrowserNativePageSurfaceLifecycle)?.presentationGeometryDidChange()
            }
            .accessibilityLabel(page.live.title.isEmpty ? "Web page" : page.live.title)
            // A covered page shows its cover from the start, in place of the
            // card's own background.
            .opacity(
                BrowserPageSurfacePresentation.revealsWebContent(
                    committedNavigationCount: page.committedNavigationCount
                ) || page.shownPaintCover != nil ? 1 : 0
            )

            BrowserPageLoadingPresentation(page: page)

            if let hover = page.linkHover { BrowserLinkHoverPreview(hover: hover) }

            if page.isFindPresented {
                BrowserFindBar(
                    port: findPort,
                    capabilities: capabilities,
                    isPageActive: isPageActive
                )
                .padding(BrowserWebPageSurfaceMetrics.overlayPadding)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topTrailing
                )
            }

            if !page.visibleEngineInfoBars.isEmpty {
                BrowserEngineInfoBarStack(page: page, goToSharingCounterpart: goToSharingCounterpart)
            }

            if let agent, let pointer = page.agentPointer {
                BrowserAgentPointerOverlay(pointer: pointer, session: agent, zoom: page.renderedPageZoom)
                    .zIndex(BrowserWebPageSurfaceMetrics.agentPointerZIndex)
            }

            // The bars along the page's foot stack, the picker's above an
            // agent's.
            VStack(spacing: BrowserWebPageSurfaceMetrics.overlayPadding) {
                if page.elementPicker.isActive {
                    BrowserElementPickerBar(picker: page.elementPicker)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let agent {
                    // The bar needs its tab to show the agent's pending site request for it.
                    BrowserAgentPageBar(session: agent, tabID: browser.core.state.pages[page.corePage.id]?.tabID) {
                        if let tabID = browser.core.state.pages[page.corePage.id]?.tabID {
                            _ = try? browser.core.send(StopAgentTab(tabID: tabID))
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(BrowserWebPageSurfaceMetrics.overlayPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            BrowserWebPageFailureOverlay(
                page: page,
                branding: browser.spaceModel(
                    matching: BrowserSpaceRuntimeAssignment(spaceID: page.spaceID, profileID: page.profileID)
                ).map(\.settings.look),
                pagePresentation: pagePresentation
            )

            BrowserCredentialChrome(
                presentation: BrowserCredentialChromePresentation.resolve(
                    saveCandidate: page.credentialSaveCandidate,
                    fillRequest: page.credentialFillRequest
                ),
                fillPort: credentialFillPort,
                savePort: credentialSavePort,
                browser: browser,
                capabilities: capabilities
            )

            if page.isRegionCapturePresented {
                BrowserRegionCaptureOverlay(page: page)
                    .zIndex(BrowserWebPageSurfaceMetrics.regionCaptureZIndex)
            }

            if let offer = page.shareSourceOffer {
                BrowserShareSourcePicker(
                    offer: offer.keeping(offersPage), requestingPageID: page.corePage.id, tabPlacement: tabPlacement,
                    requestingTabName: tabPlacement(page.corePage.id)?.name ?? page.live.title
                ) { choice in
                    page.answer(offer, with: choice)
                }
                .id(offer.id)
                .zIndex(BrowserWebPageSurfaceMetrics.sharePickerZIndex)
            }

            if let feedback = page.developerCaptureFeedback {
                BrowserDeveloperCaptureFeedbackView(feedback: feedback)
                    .zIndex(BrowserWebPageSurfaceMetrics.feedbackZIndex)
            }
        }
        .animation(reduceMotion ? nil : OdeMotion.step, value: page.elementPicker.isActive)
    }

    /// The questions the find bar asks, bound to this surface's page.
    private var findPort: BrowserFindPort {
        BrowserFindPort(
            find: { query, direction in
                page.find(query, direction: direction)
            },
            query: { page.findQuery },
            matchState: { page.findMatchState },
            matches: { page.findMatches },
            focusRequest: { page.findFocusRequest },
            focusesQueryField: { page.findFocusesQueryField },
            dismiss: page.dismissFind
        )
    }

    /// What a credential fill prompt asks of this surface's page.
    ///
    /// The zoom is carried because this shell anchors the prompt under the
    /// field that raised it, and the page reports that field in its own CSS
    /// pixels. The chrome is a sibling of the web view inside one box, so the
    /// zoom is the only thing between the two.
    private var credentialFillPort: BrowserCredentialFillPort {
        BrowserCredentialFillPort(
            spaceID: page.spaceID,
            contentScale: page.renderedPageZoom,
            siteIconData: page.faviconData,
            fill: { credential, requestID in
                try await page.fillCredential(credential, for: requestID)
            },
            fillGeneratedPassword: { password, requestID in
                try await page.fillGeneratedPassword(password, for: requestID)
            },
            dismiss: page.dismissCredentialFillRequest
        )
    }

    /// What the save prompt asks of this surface's page. This shell makes no
    /// offer to the system's Passwords app, so it binds none.
    private var credentialSavePort: BrowserCredentialSavePort {
        BrowserCredentialSavePort(
            spaceID: page.spaceID,
            presentedCandidateID: { page.credentialSaveCandidate?.id },
            dismiss: page.dismissCredentialSaveCandidate,
            offerToSystemPasswords: nil
        )
    }

    /// What this shell can do: a pointer rests over the chrome and nothing is
    /// aimed at with a finger.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }
}

private struct BrowserPageLoadingPresentation: View {
    /// How long a page's first load runs before the surface says it is
    /// opening. A load that finishes sooner goes straight from the page
    /// before to the page, as a browser's does, with nothing in between.
    private static let initialLoadingStatusDelay: Duration = .milliseconds(400)
    /// A load that finishes within this never shows the bar.
    private static let loadBarDelay: Duration = .milliseconds(150)
    /// How long a finished load's bar takes to reach the end and fade.
    private static let loadBarFinish: Duration = .milliseconds(420)
    private static let loadBarFade = Animation.easeOut(duration: 0.24)
    private static let loadBarFadeDelay: TimeInterval = 0.12

    /// The load bar's phase: hidden until a load has run a moment, then
    /// following the engine's progress, then filling to the end and fading
    /// when the load finishes rather than vanishing part-way.
    private enum LoadBar {
        case hidden, showing, finishing
    }

    /// The load bar's height along the top of the page.
    private static let loadBarHeight: CGFloat = 2

    let page: BrowserPage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the first load has run long enough to say the page is opening.
    @State private var initialStatusIsDue = false
    @State private var loadBar = LoadBar.hidden

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if showsInitialStatus, initialStatusIsDue {
                    initialStatus
                }
            }
            .task(id: showsInitialStatus) {
                initialStatusIsDue = false
                guard showsInitialStatus else { return }
                try? await Task.sleep(for: Self.initialLoadingStatusDelay)
                guard !Task.isCancelled else { return }
                initialStatusIsDue = true
            }
            .task(id: isNavigating) {
                if isNavigating {
                    loadBar = .hidden
                    try? await Task.sleep(for: Self.loadBarDelay)
                    guard !Task.isCancelled, isNavigating else { return }
                    loadBar = .showing
                } else if loadBar == .showing {
                    loadBar = .finishing
                    try? await Task.sleep(for: Self.loadBarFinish)
                    guard !Task.isCancelled else { return }
                    loadBar = .hidden
                }
            }
            .overlay(alignment: .top) {
                loadingProgress
            }
            .allowsHitTesting(false)
    }

    private var initialStatus: some View {
        VStack(spacing: BrowserWebPageSurfaceMetrics.initialLoadingSpacing) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            openingLabel
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("browser-initial-loading-status")
    }

    private var loadingProgress: some View {
        Rectangle()
            .fill(.tint)
            .frame(height: Self.loadBarHeight)
            .scaleEffect(x: loadBar == .finishing ? 1 : progress, anchor: .leading)
            .opacity(loadBar == .showing ? 1 : 0)
            .animation(
                OdeMotion.loadingProgress.unlessReducingMotion(reduceMotion),
                value: progress
            )
            .animation(
                loadBar == .finishing ? Self.loadBarFade.delay(Self.loadBarFadeDelay) : Self.loadBarFade,
                value: loadBar
            )
            .accessibilityHidden(true)
    }

    private var openingLabel: Text {
        guard let host = page.live.displayURL?.host(), !host.isEmpty else {
            return Text(
                "Opening page…",
                comment: "Initial status while a web page begins navigating."
            )
        }
        return Text(
            "Opening \(host)…",
            comment: "Initial page loading status; the value is the destination host."
        )
    }

    private var isNavigating: Bool {
        // Same-document destinations can remain pending without a WebKit load.
        // Only use the destination to bridge a fresh page's initial loading gap.
        page.live.isLoading || (page.live.pendingNavigationURL != nil && page.committedNavigationCount == 0)
    }

    private var hasFailure: Bool {
        page.live.failure != nil || page.webContentFailureMessage != nil
    }

    private var showsInitialStatus: Bool {
        isNavigating && page.committedNavigationCount == 0 && !hasFailure
    }

    private var progress: CGFloat {
        BrowserPageSurfacePresentation.loadingProgress(
            estimatedProgress: page.estimatedProgress,
            isNavigating: isNavigating
        )
    }
}
