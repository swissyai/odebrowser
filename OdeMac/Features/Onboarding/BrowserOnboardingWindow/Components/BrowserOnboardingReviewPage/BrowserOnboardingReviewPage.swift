import AppKit
import SwiftUI

/// Reviewing what one browser brings, one Space at a time: the browser's
/// sidebar on the left, Ode's on the right wearing the look setup chose,
/// and between them what the Space brings along.
struct BrowserOnboardingReviewPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let flow: BrowserOnboardingFlow
    @Binding var customizationSpaceID: UUID?
    let back: BrowserOnboardingBackAction

    /// The Space the scroll shows. Setup learns it once the scroll settles,
    /// so moving through the review changes nothing setup holds mid-scroll.
    @State private var scrolledSpaceID: UUID?

    var body: some View {
        if let setupReview = flow.review, flow.isExplainingKeychain {
            BrowserOnboardingKeychainPage(
                browserTitle: setupReview.title,
                wasRefused: flow.keychainWasRefused,
                isImporting: flow.isCommittingImport,
                back: flow.dismissKeychainExplanation,
                continueImport: { flow.commitReviewedImport(afterExplaining: true) },
                importWithoutSecrets: flow.importWithoutSecrets
            )
        } else if let setupReview = flow.review,
            let review = flow.selectedReview(id: scrolledSpaceID ?? setupReview.shownSpaceID)
        {
            let spaces = flow.reviewSpaces
            VStack(spacing: 0) {
                BrowserOnboardingReviewHeader(
                    icon: sourceIcon,
                    title: setupReview.title,
                    progressLabel: flow.reviewProgressLabel(for: review)
                )
                .disabled(flow.isCommittingImport)

                // The browser's Spaces stack under one another, one page each,
                // so moving between them reads as moving through that browser.
                ZStack(alignment: .trailing) {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(spaces) { item in
                                BrowserOnboardingReviewSpacePage(
                                    flow: flow,
                                    application: setupReview.source,
                                    spaces: spaces,
                                    review: item,
                                    leftOut: setupReview.leftOut,
                                    customize: { customizationSpaceID = item.id }
                                )
                                .containerRelativeFrame(.vertical)
                                .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $scrolledSpaceID, anchor: .top)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                    .onScrollPhaseChange { _, phase in
                        if phase == .idle, let scrolledSpaceID { flow.shownReviewSpaceID = scrolledSpaceID }
                    }

                    BrowserOnboardingReviewSpaceStepper(spaces: spaces, selectedSpaceID: review.id, select: show)
                }
                .disabled(flow.isCommittingImport)
                .onAppear { scrolledSpaceID = setupReview.shownSpaceID }
                .onChange(of: setupReview.shownSpaceID) { _, shown in
                    if let shown, shown != scrolledSpaceID { scrolledSpaceID = shown }
                }

                BrowserOnboardingFooter(back: back, isBackDisabled: flow.isCommittingImport) {
                    HStack(spacing: 18) {
                        footerNotes(setupReview)
                        if flow.reviewSpace(after: review.id) != nil {
                            Button("Next Space") { advance(from: review.id) }
                                .buttonStyle(.odeSecondary)
                                .fixedSize()
                                .disabled(flow.isCommittingImport)
                                .accessibilityIdentifier("onboarding-review-next-space")
                        }
                        // Importing is offered on every page, so a person who
                        // trusts the defaults never pages through every Space.
                        BrowserOnboardingContinueButton(importTitle) {
                            flow.commitReviewedImport()
                        }
                        .disabled(flow.isCommittingImport || !setupReview.hasIncludedSpaces)
                        .accessibilityIdentifier("onboarding-confirm-import")
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Nothing to Review",
                systemImage: "checklist.unchecked",
                description: Text("Choose a browser to build an import review.")
            )
        }
    }

    /// What the footer says beside its buttons: a failure, else what the
    /// import brings, the passwords choice, why passwords were left out, and
    /// the empty Spaces folded away.
    @ViewBuilder
    private func footerNotes(_ setupReview: SetupImportReview) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let failure = flow.failure?.message {
                Label {
                    BrowserOnboardingFailureMessage(message: failure)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(OdeTypography.sans(12, weight: .medium))
                .foregroundStyle(SpaceRoleStyle.dangerText)
                .lineLimit(3)
                .frame(maxWidth: 420, alignment: .trailing)
                .accessibilityIdentifier("onboarding-workflow-error")
            } else if let summary = flow.reviewSummary() {
                Text(summary)
                    .font(OdeTypography.sans(13, weight: .medium))
                    .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.7))
                    .lineLimit(2)
                    .frame(maxWidth: 420, alignment: .trailing)
            }
            if setupReview.source == .arc {
                signInImportChoice
            }
            if !setupReview.extensionInstalls.isEmpty {
                Text(
                    "Selected extensions download and install after you open Ode, with their requested default permissions. They aren't installed yet."
                )
                .font(OdeTypography.sans(12, weight: .medium))
                .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.7))
                .frame(maxWidth: 420, alignment: .trailing)
            }
            HStack(spacing: 14) {
                if flow.emptyReviewSpaceCount > 0 {
                    Button(
                        flow.showsEmptyReviewSpaces
                            ? String(localized: "Hide Empty Spaces")
                            : String(localized: "Show \(flow.emptyReviewSpaceCount) Empty Spaces")
                    ) {
                        flow.showsEmptyReviewSpaces.toggle()
                    }
                    .buttonStyle(.link)
                    .odeControlPointer()
                    .font(OdeTypography.sans(12, weight: .medium))
                    .accessibilityIdentifier("onboarding-review-empty-spaces")
                }
                if let passwordNote = passwordNote(setupReview) {
                    Text(passwordNote)
                        .font(OdeTypography.sans(12, weight: .medium))
                        .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.7))
                        .lineLimit(2)
                        .frame(maxWidth: 320, alignment: .trailing)
                        .accessibilityIdentifier("onboarding-review-password-note")
                } else if setupReview.source.suppliesPasswords {
                    Toggle(
                        "Bring saved passwords",
                        isOn: Binding(
                            get: { flow.bringsPasswords },
                            set: { flow.setBringsPasswords($0) })
                    )
                    .toggleStyle(.checkbox)
                    .odeControlPointer()
                    .font(OdeTypography.sans(12, weight: .medium))
                    .fixedSize()
                    .accessibilityIdentifier("onboarding-review-passwords")
                }
            }
        }
    }

    @ViewBuilder
    private var signInImportChoice: some View {
        Toggle(
            "Bring Arc sign-ins into new Spaces",
            isOn: Binding(get: { flow.bringsSignIns }, set: { flow.setBringsSignIns($0) })
        )
        .toggleStyle(.checkbox)
        .odeControlPointer()
        .font(OdeTypography.sans(12, weight: .medium))
        .disabled(!flow.supportsSignInCarry)
        Text(
            flow.supportsSignIns
                ? String(
                    localized:
                        "Sign-ins aren't merged into existing Spaces. Some sites may still ask you to sign in.")
                : String(localized: "Sign-in import isn't available in this build.")
        )
        .font(OdeTypography.sans(12, weight: .medium))
        .foregroundStyle(OdeBrandTheme.textDisplay.opacity(0.7))
    }

    /// Why the review brings no passwords, when the browser's could not be
    /// read; the rest comes over regardless.
    private func passwordNote(_ setupReview: SetupImportReview) -> LocalizedStringResource? {
        guard flow.passwordReadFailure != nil else { return nil }
        return LocalizedStringResource(
            "\(setupReview.title)'s passwords couldn't be read. Other selected data can still be imported; to retry passwords, quit \(setupReview.title) and import again.",
            comment: "Setup's review footer when the source browser's passwords could not be read.")
    }

    private var importTitle: Text {
        flow.isCommittingImport ? Text("Importing…") : Text(flow.importReviewActionTitle)
    }

    private func advance(from spaceID: UUID) {
        if let nextID = flow.reviewSpace(after: spaceID) { show(nextID) }
    }

    private var sourceIcon: NSImage? {
        flow.review.flatMap { flow.offeredSource($0.source) }?.icon
    }

    /// Scrolls to `spaceID`, and tells setup once the scroll arrives, unless
    /// a later press or a scroll has moved on from it by then.
    private func show(_ spaceID: UUID) {
        withAnimation(motion(OdeMotion.onboardingProgress)) {
            scrolledSpaceID = spaceID
        } completion: {
            if scrolledSpaceID == spaceID { flow.shownReviewSpaceID = spaceID }
        }
    }

    private func motion(_ animation: Animation) -> Animation? {
        animation.unlessReducingMotion(reduceMotion)
    }
}

/// The browser under review, and which of its Spaces this is.
private struct BrowserOnboardingReviewHeader: View {
    let icon: NSImage?
    let title: String
    let progressLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Review \(title)")
                    .font(OdeTypography.display(30))
                    .foregroundStyle(OdeBrandTheme.textDisplay)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(progressLabel)
                    .font(OdeTypography.sans(12, weight: .semibold))
                    .foregroundStyle(OdeBrandTheme.textSecondary)
            }
            Spacer(minLength: 20)
        }
        .padding(.horizontal, BrowserOnboardingStageMetrics.pageInset)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

/// Where the shown Space stands among the browser's, down the right edge.
private struct BrowserOnboardingReviewSpaceStepper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let spaces: [BrowserImportSpaceReview]
    let selectedSpaceID: UUID?
    /// Shows a Space's page, from a click on its mark.
    let select: (UUID) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(groups, id: \.[0].id) { group in
                // The Spaces that come in as one group share an outline.
                VStack(spacing: 6) {
                    ForEach(group) { item in step(item) }
                }
                .padding(group.count > 1 ? 5 : 0)
                .overlay {
                    if group.count > 1 {
                        Capsule(style: .continuous)
                            .strokeBorder(OdeBrandTheme.textDisplay.opacity(0.35), lineWidth: OdeLayout.hairline)
                    }
                }
            }
        }
        // Its own gutter at the page's edge, clear of the right column.
        .padding(.trailing, BrowserOnboardingStageMetrics.inset / 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space review progress")
    }

    /// The reviewed Spaces in order, split where one group ends and the next
    /// begins. Spaces the review leaves out stand on their own.
    private var groups: [[BrowserImportSpaceReview]] {
        var groups: [[BrowserImportSpaceReview]] = []
        for item in spaces {
            if let last = groups.last?.last, last.isIncluded, item.isIncluded, last.groupID == item.groupID {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
        }
        return groups
    }

    private func step(_ item: BrowserImportSpaceReview) -> some View {
        let isCurrent = item.id == selectedSpaceID
        return Button {
            select(item.id)
        } label: {
            Capsule(style: .continuous)
                .fill(isCurrent ? OdeBrandTheme.accent : OdeBrandTheme.textDisplay.opacity(0.3))
                .frame(width: isCurrent ? 8 : 6, height: isCurrent ? 32 : 6)
                .frame(width: 20, height: isCurrent ? 36 : 12)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .odeControlPointer()
        .animation(OdeMotion.onboardingProgress.unlessReducingMotion(reduceMotion), value: selectedSpaceID)
        .help(item.sourceSpace.settings.name)
        .accessibilityLabel(item.sourceSpace.settings.name)
        .accessibilityValue(isCurrent ? "Current Space" : "Space in review")
    }
}

/// Import notices, including reasons that describe quantities of omitted
/// data rather than a single item. Details keep those quantities intact.
struct BrowserOnboardingReviewLeftOutMenu: View {
    // MARK: - Variables

    let leftOut: [ImportLeftOut]
    @State private var showsNotices = false

    var body: some View {
        Button {
            showsNotices = true
        } label: {
            Label {
                Text(BrowserOnboardingSummary.noticeCount(leftOut.count))
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(OdeTypography.sans(12, weight: .semibold))
        }
        .buttonStyle(.odeSecondary)
        .fixedSize()
        .accessibilityHint("Shows what the import leaves out and why")
        .odePopover(isPresented: $showsNotices) {
            ScrollView {
                VStack(alignment: .leading, spacing: OdeSpacing.medium) {
                    Text("Import notices")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(leftOut.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: OdeSpacing.extraSmall) {
                            Text(item.name).font(.subheadline.weight(.semibold))
                            Text(item.reason.explanation).font(.callout)
                        }
                        .foregroundStyle(.primary)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OdeSpacing.medium)
            }
            .frame(width: 420)
            .frame(maxHeight: 360)
        }
    }
}
