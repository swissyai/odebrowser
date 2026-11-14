import SwiftUI

struct BrowserOnboardingWindowContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let request: BrowserOnboardingRequest
    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore
    let flow: BrowserOnboardingFlow
    let cloudWait: BrowserOnboardingCloudWait
    @Binding var selectedManualSpaceID: UUID?
    @Binding var customizationSpaceID: UUID?
    let close: () -> Void
    let openOde: () -> Void
    let skipOnboarding: () -> Void

    var body: some View {
        BrowserOnboardingStage(step: flow.step, branding: stageBranding) {
            VStack(spacing: 0) {
                if let customizationSpaceID, flow.review != nil {
                    BrowserImportSpaceCustomizationView(
                        flow: flow,
                        spaceID: customizationSpaceID,
                        previewSpace: flow.customizationPreviewSpace(
                            customizationSpaceID
                        ),
                        done: { self.customizationSpaceID = nil }
                    )
                } else {
                    BrowserOnboardingStepContent(
                        cloudSync: cloudSync,
                        progress: progress,
                        flow: flow,
                        cloudWait: cloudWait,
                        selectedManualSpaceID: $selectedManualSpaceID,
                        customizationSpaceID: $customizationSpaceID,
                        close: close,
                        openOde: openOde
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let failure = flow.completionFailure {
                    Text(failure)
                        .foregroundStyle(SpaceRoleStyle.dangerText)
                        .padding()
                }
            }
            .disabled(flow.isCompletingSetup)
            .overlay {
                if let stage = flow.importStage {
                    BrowserOnboardingImportStageView(stage: stage)
                        .transition(.opacity)
                }
            }
            .animation(motion(OdeMotion.onboardingStep), value: flow.importStage == nil)
        }
        .overlay(alignment: .topTrailing) {
            if flow.step != .practice && flow.step != .complete {
                Button("Skip setup", action: skipToEnd)
                    .buttonStyle(.odeSecondary)
                    .disabled(flow.isCommittingImport || flow.isCompletingSetup)
                    .accessibilityHint("Opens Ode without applying unfinished setup choices. Imported data is kept.")
                    .padding(.horizontal, BrowserOnboardingStageMetrics.headerInset)
                    .frame(height: BrowserOnboardingStageMetrics.headerHeight)
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        .tint(OdeBrandTheme.accent)
        .environment(\.odeUsesPointingHandControls, true)
        .background(BrowserOnboardingWindowConfigurator())
        .task {
            await start()
        }
        .task {
            await cloudWait.run()
        }
        .onChange(of: request) { _, newRequest in
            resetTransientState(for: newRequest)
        }
        .onChange(of: flow.step) { _, step in
            if step == .manualSetup { flow.manualSetup.repairSelection($selectedManualSpaceID) }
        }
        .onDisappear(perform: flow.cancelOperations)
        .animation(motion(OdeMotion.onboardingStep), value: flow.step)
    }

    /// Only an edited or reviewed Space overrides Ode's ordinary canvas.
    private var stageBranding: SpaceBranding? {
        switch flow.step.kind {
        case .manualSetup, .practice:
            return flow.manualSetup.space(selectedManualSpaceID)?.customization.branding ?? flow.look.previewBranding
        case .review:
            guard let review = flow.selectedReview(id: flow.shownReviewSpaceID) else {
                return flow.look.previewBranding
            }
            return flow.previewDestinationSpace(for: review)?.settings.look ?? flow.look.previewBranding
        case .complete:
            return flow.manualSetup.spaces.first?.customization.branding ?? flow.look.previewBranding
        case .welcome, .look, .layout, .featureSpaces, .featureTabs, .featureSync, .importBrowser:
            return nil
        }
    }

    private func skipToEnd() {
        guard flow.prepareToSkipToEnd() else { return }
        skipOnboarding()
    }

    private func start() async {
        flow.start()
        flow.discoverInstalledSources()
        flow.manualSetup.repairSelection($selectedManualSpaceID)
    }

    private func resetTransientState(for request: BrowserOnboardingRequest) {
        customizationSpaceID = nil
        withAnimation(motion(OdeMotion.onboardingStep)) {
            flow.reset(for: request)
        }
        selectedManualSpaceID = flow.manualSetup.spaces.first?.spaceID
    }

    private func motion(_ animation: Animation) -> Animation? {
        animation.unlessReducingMotion(reduceMotion)
    }
}
