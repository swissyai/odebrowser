import SwiftUI

/// A small working example backed by its own memory-only core. Navigation
/// belongs to the host directly below this view and never requires success.
struct BrowserOnboardingTabLesson: View {
    // MARK: - Variables

    let branding: SpaceBranding
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var practice = BrowserGettingStartedPractice()
    @State private var showsSave = false

    private var completed: Bool {
        guard let id = practice.tabID(showsSave ? .trail : .mail) else { return false }
        return practice.space.tabs.model(id)?.placement == (showsSave ? .saved : .pinned)
    }

    // MARK: - Actions - Presentation

    var body: some View {
        VStack(alignment: .leading, spacing: OdeSpacing.large) {
            Text(showsSave ? "Keep a tab for later" : "Keep a favorite close")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            BrowserGettingStartedPracticeSidebar(
                practice: practice, capabilities: capabilities, showsHeader: false, backgroundBranding: branding
            )
            .frame(height: 280)
            .clipShape(.rect(cornerRadius: OdeCornerScale.surface))
            .overlay {
                RoundedRectangle(cornerRadius: OdeCornerScale.surface).strokeBorder(OdeBrandTheme.line)
            }
            Group {
                if completed {
                    Label(
                        showsSave ? "Saved. It stays until you remove it." : "Pinned. Gmail is now at the top.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(SpaceRoleStyle.accentText)
                    .accessibilityElement(children: .combine)
                } else if showsSave {
                    BrowserGettingStartedSaveAction(
                        practice: practice, title: "Save A weekend away", systemImage: "bookmark", style: .odePrimary
                    )
                    .controlSize(.large)
                } else {
                    BrowserGettingStartedPinAction(practice: practice, style: .odePrimary)
                        .controlSize(.large)
                }
            }
            .frame(minHeight: OdeLayout.minimumHitTarget, alignment: .leading)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OdeSpacing.large) { lessonActions }
                VStack(alignment: .leading, spacing: OdeSpacing.small) { lessonActions }
            }
            Text("These example tabs are temporary. Your tabs stay unchanged.")
                .font(.footnote)
                .foregroundStyle(SpaceRoleStyle.secondaryText)
        }
        .environment(practice.sidebarInteraction)
        .onDisappear { practice.sidebarInteraction.cancel() }
        .animation(
            OdeMotion.collection.unlessReducingMotion(reduceMotion), value: practice.space.sidebar.lists.map(\.rows))
    }

    @ViewBuilder private var lessonActions: some View {
        Button {
            showsSave.toggle()
        } label: {
            Label(showsSave ? "Try pinning" : "Try saving", systemImage: "arrow.right")
                .font(.body.weight(.semibold))
                .frame(minHeight: OdeLayout.minimumHitTarget)
        }
        .buttonStyle(.odeSecondary)
        .controlSize(.large)
        Button {
            practice.reset()
        } label: {
            Label("Reset example", systemImage: "arrow.counterclockwise")
                .font(.body.weight(.semibold))
                .frame(minHeight: OdeLayout.minimumHitTarget)
        }
        .buttonStyle(.odeSecondary)
        .controlSize(.large)
    }
}
