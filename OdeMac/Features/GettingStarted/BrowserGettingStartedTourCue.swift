import SwiftUI

/// One instruction beside the action, shared by the guide and real palette.
struct BrowserGettingStartedTourCue: View {
    // MARK: - Variables

    let tour: BrowserGettingStartedTour
    let runCommand: (ShortcutCommand) -> Bool
    var compact = false
    @State private var couldNotRun = false

    private var cue: LocalizedStringKey {
        if couldNotRun { return "Try that again." }
        if tour.step == .commandBar || tour.step == .answer && !tour.isCommandBarPresented {
            return "Open the Command Bar"
        }
        if tour.step == .answer {
            if tour.answerIsReady { return "Copy this answer" }
            return tour.answerIsAvailable ? "Choose an answer" : "Type 12 * 3"
        }
        if tour.step == .sidebar { return tour.sidebarIsPresented ? "Hide the sidebar" : "Show the sidebar" }
        return tour.isCommandBarPresented ? "Type get started" : "Find “get started”"
    }

    private var shownShortcut: BrowserShortcut? { tour.heldShortcut ?? tour.expectedShortcut }

    // MARK: - Actions - Presentation

    var body: some View {
        VStack(spacing: compact ? OdeSpacing.small : OdeSpacing.large) {
            if tour.expectedShortcut == nil, tour.step != .answer, tour.step != .finished, tour.heldShortcut == nil {
                Button(cue) { perform() }.buttonStyle(.odePrimary)
            } else {
                Text(cue)
                    .font(OdeTypography.display(compact ? 22 : 32))
                    .accessibilityAddTraits(.isHeader)
                if let shownShortcut {
                    if shownShortcut == tour.expectedShortcut {
                        Button {
                            perform()
                        } label: {
                            keys(shownShortcut)
                        }
                        .buttonStyle(OdeChromeButtonStyle(controlSize: nil, cornerRadius: OdeRadius.control))
                        .accessibilityLabel(Text(cue))
                    } else {
                        keys(shownShortcut)
                    }
                }
            }
            if let completed = tour.completedShortcut, tour.heldShortcut == nil {
                HStack(spacing: OdeSpacing.small) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(OdeBrandTheme.accent)
                    BrowserGettingStartedTourKeycaps(
                        keys: completed.keycapLabels, confirmed: true, compact: true,
                        spokenDescription: completed.spokenDescription)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Completed: \(completed.spokenDescription)"))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .onChange(of: tour.step) { couldNotRun = false }
        .onChange(of: tour.answerIsReady) { couldNotRun = false }
    }

    private func keys(_ shortcut: BrowserShortcut) -> some View {
        BrowserGettingStartedTourKeycaps(
            keys: shortcut.keycapLabels, confirmed: false,
            pressedKeys: tour.pressedKeys(for: shortcut), small: compact,
            spokenDescription: shortcut.spokenDescription)
    }

    private func perform() {
        if tour.step == .answer, tour.isCommandBarPresented {
            couldNotRun = !tour.copyAnswer()
        } else {
            couldNotRun = !runCommand(tour.step == .sidebar ? .toggleSidebar : .newTab)
        }
    }
}
