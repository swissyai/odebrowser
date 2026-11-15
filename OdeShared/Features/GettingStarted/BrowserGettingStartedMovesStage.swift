#if os(macOS)
    import SwiftUI

    /// One move at a time, with the real feature's completion kept until Next.
    struct BrowserGettingStartedMovesStage: View {
        let moves: BrowserGettingStartedMoves
        @Binding var selection: BrowserGettingStartedMove?
        let runCommand: (ShortcutCommand) -> Bool
        var context: BrowserGettingStartedGuideContext? = nil
        var openSearchSettings: () -> Bool = { false }
        var practiceSplit: () -> Void = {}
        var compact = false

        @Environment(BrowserGettingStartedTour.self) private var tour: BrowserGettingStartedTour?
        @State private var couldNotRun = false

        private var shown: BrowserGettingStartedMove? { selection ?? moves.next }

        var body: some View {
            VStack(spacing: compact ? OdeSpacing.medium : OdeSpacing.extraExtraLarge) {
                Spacer(minLength: 0)
                if let shown {
                    move(shown)
                } else {
                    Text("All yours").font(OdeTypography.display(32))
                    Button("Try another move", systemImage: "arrow.counterclockwise") {
                        moves.reset()
                        selection = .commandBar
                    }
                    .buttonStyle(.odeSecondary)
                }
                Image(decorative: "OdeWelcomeBeret").resizable().scaledToFit()
                    .frame(height: compact ? 48 : 100)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                HStack(spacing: OdeSpacing.large) {
                    Text("\(moves.done.count) of \(BrowserGettingStartedMove.allCases.count) done")
                        .font(OdeTypography.sans(13)).foregroundStyle(OdeBrandTheme.textSecondary)
                    if let shown {
                        Button(moves.done.contains(shown) ? "Next" : "Skip", systemImage: "arrow.right") {
                            selection = moves.next(after: shown)
                        }
                        .buttonStyle(.odeSecondary)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .onAppear { if selection == nil { selection = moves.next } }
            .onChange(of: shown) { couldNotRun = false }
        }

        private func move(_ move: BrowserGettingStartedMove) -> some View {
            VStack(spacing: OdeSpacing.medium) {
                Text(move.cue).font(OdeTypography.display(compact ? 26 : 32))
                Text(couldNotRun ? "This action is no longer available." : hint(for: move))
                    .font(OdeTypography.sans(15)).foregroundStyle(OdeBrandTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let consequence = move.consequence {
                    Text(consequence).font(OdeTypography.sans(13)).foregroundStyle(OdeBrandTheme.textSecondary)
                }
                if needsSearchSetup(move) {
                    Button("Open Search settings", systemImage: "gearshape") {
                        couldNotRun = !openSearchSettings()
                    }
                    .buttonStyle(.odeSecondary)
                } else if move == .splitView, context?.canSplit != true {
                    Button("Try Split View", systemImage: "rectangle.split.2x1", action: practiceSplit)
                        .buttonStyle(.odeSecondary)
                } else if let command = move.demonstration,
                    move != .switchSpace || context?.hasOtherSpace == true
                {
                    Button {
                        couldNotRun = !runCommand(command)
                    } label: {
                        if let shortcut = tour?.shortcut(for: command) {
                            BrowserGettingStartedTourKeycaps(
                                keys: shortcut.keycapLabels, confirmed: moves.done.contains(move), small: compact,
                                spokenDescription: shortcut.spokenDescription)
                        } else {
                            Label("Try it", systemImage: "play")
                        }
                    }
                    .buttonStyle(OdeChromeButtonStyle(controlSize: nil, cornerRadius: OdeRadius.control))
                    .accessibilityLabel(Text(verbatim: move.title))
                }
            }
            .frame(maxWidth: 480)
            .accessibilityElement(children: .contain)
            .accessibilityValue(Text(moves.done.contains(move) ? "Done" : "Not yet"))
        }

        private func needsSearchSetup(_ move: BrowserGettingStartedMove) -> Bool {
            (move == .siteSearch || move == .askAI) && context?.keyword(for: move) == nil
        }

        private func hint(for move: BrowserGettingStartedMove) -> LocalizedStringResource {
            if move == .siteSearch || move == .askAI {
                if let keyword = context?.keyword(for: move) { return "Type \(keyword) in the Command Bar." }
                if context?.searchesWithTab == false { return "Turn on Tab to search providers in Search settings." }
            }
            if move == .switchSpace, context?.hasOtherSpace != true {
                return "Show the sidebar, then right-click an empty area and choose New Space…"
            }
            if move == .splitView, context?.canSplit != true { return "Try it with two example pages." }
            return move.hint
        }
    }
#endif
