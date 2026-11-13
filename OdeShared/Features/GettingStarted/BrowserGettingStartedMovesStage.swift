#if os(macOS)
    import SwiftUI

    /// The everyday moves, taught in the person's own window: one card for
    /// the move at hand, in the words of the Command Bar's written answer,
    /// with its keys and a "Show me" that starts it; the seven moves beside
    /// it, each checked off when the person makes it anywhere in Ode.
    struct BrowserGettingStartedMovesStage: View {
        let moves: BrowserGettingStartedMoves
        @Binding var selection: BrowserGettingStartedMove?
        let wide: Bool
        let runCommand: (ShortcutCommand) -> Bool

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.browserChromeAppearance) private var chromeAppearance

        /// How long a move stays on screen, checked, before the next one
        /// comes in.
        private static let advanceDelay: Duration = .milliseconds(900)

        var body: some View {
            Group {
                if wide {
                    HStack(alignment: .top, spacing: 32) {
                        guide.frame(width: 380, alignment: .topLeading)
                        moveList.frame(maxWidth: 460, alignment: .topLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        guide
                        moveList
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .task(id: moves.done) { await advanceIfDone() }
        }

        // MARK: - Parts

        private var guide: some View {
            VStack(alignment: .leading, spacing: 16) {
                BrowserGettingStartedMoveMarks(moves: moves, shown: shown)
                Group {
                    if let shown {
                        BrowserGettingStartedMoveCard(
                            move: shown, isDone: moves.done.contains(shown), runCommand: runCommand,
                            advance: { select(nextMove(after: shown)) }
                        )
                        .id(shown)
                        .transition(cardTransition)
                    } else {
                        completion.transition(cardTransition)
                    }
                }
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.32), value: shown)
            }
        }

        private var completion: some View {
            VStack(alignment: .leading, spacing: 12) {
                Label("All seven done", systemImage: "checkmark.circle.fill")
                    .font(OdeTypography.display(24))
                    .foregroundStyle(OdeBrandTheme.accent)
                Text("The Command Bar can answer anything else. Type a question, such as how do I lock a Space.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start Over", systemImage: "arrow.counterclockwise") {
                    moves.reset()
                    select(.commandBar)
                }
                .buttonStyle(.odeSecondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(BrowserGettingStartedCardSurface())
        }

        private var moveList: some View {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(BrowserGettingStartedMove.allCases) { move in
                    Button {
                        select(move)
                    } label: {
                        HStack(spacing: 10) {
                            BrowserGettingStartedMoveCheck(isDone: moves.done.contains(move), size: 17)
                            Text(verbatim: move.title)
                                .font(OdeTypography.sans(13, weight: move == shown ? .semibold : .regular))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if let keys = move.keys { BrowserGettingStartedKeys(keys: keys) }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            move == shown ? Color.primary.opacity(0.07) : .clear,
                            in: .rect(cornerRadius: chromeAppearance.cornerScale.row, style: .continuous)
                        )
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(move == shown ? .isSelected : [])
                    .accessibilityValue(Text(moves.done.contains(move) ? "Done" : "Not yet"))
                }
            }
        }

        // MARK: - State

        /// The move the card shows: the one chosen, else the first not done.
        private var shown: BrowserGettingStartedMove? {
            selection ?? moves.next
        }

        private var cardTransition: AnyTransition {
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 12)),
                    removal: .opacity.combined(with: .offset(x: -12)))
        }

        private func select(_ move: BrowserGettingStartedMove?) {
            selection = move
        }

        /// The next move not done after `move`, wrapping, or nil when all
        /// are done.
        private func nextMove(after move: BrowserGettingStartedMove) -> BrowserGettingStartedMove? {
            let all = BrowserGettingStartedMove.allCases
            let start = all.firstIndex(of: move) ?? 0
            return (1...all.count).lazy.map { all[(start + $0) % all.count] }.first { !moves.done.contains($0) }
        }

        /// Once the move on the card is done, lets the check be seen, then
        /// brings in the next move not done.
        private func advanceIfDone() async {
            guard let shown, moves.done.contains(shown) else { return }
            try? await Task.sleep(for: Self.advanceDelay)
            guard !Task.isCancelled, self.shown == shown else { return }
            select(nextMove(after: shown))
        }
    }

    /// One move's card: its title, its steps in order, its keys, "Show me"
    /// when the window can start it, and the way on.
    private struct BrowserGettingStartedMoveCard: View {
        let move: BrowserGettingStartedMove
        let isDone: Bool
        let runCommand: (ShortcutCommand) -> Bool
        let advance: () -> Void

        @State private var couldNotShow = false

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BrowserGettingStartedMoveCheck(isDone: isDone, size: 20)
                    Text(verbatim: move.title)
                        .font(OdeTypography.display(22))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(move.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: "\(index + 1).")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(verbatim: step)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(OdeTypography.sans(14))
                if let keys = move.keys {
                    BrowserGettingStartedKeys(keys: keys)
                }
                if couldNotShow {
                    Text("Ode can't start this from here. Follow the steps in a window with a page open.")
                        .font(OdeTypography.sans(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if !isDone, let command = move.demonstration {
                        Button("Show Me", systemImage: "play.fill") {
                            couldNotShow = !runCommand(command)
                        }
                        .buttonStyle(.odePrimary)
                    }
                    Button(isDone ? "Next" : "Skip", systemImage: "arrow.right", action: advance)
                        .buttonStyle(.odeSecondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(BrowserGettingStartedCardSurface())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: move.title))
            .accessibilityValue(Text(isDone ? "Done" : "Not yet"))
        }
    }

    /// Seven marks, one for each move, filled for the moves done, the one on
    /// the card outlined.
    private struct BrowserGettingStartedMoveMarks: View {
        let moves: BrowserGettingStartedMoves
        let shown: BrowserGettingStartedMove?

        var body: some View {
            HStack(spacing: 5) {
                ForEach(BrowserGettingStartedMove.allCases) { move in
                    Capsule(style: .continuous)
                        .fill(moves.done.contains(move) ? OdeBrandTheme.accent : Color.primary.opacity(0.14))
                        .overlay {
                            if move == shown {
                                Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.55), lineWidth: 1)
                            }
                        }
                        .frame(width: 22, height: 5)
                }
            }
            .animation(OdeMotion.collection, value: moves.done)
            .accessibilityElement()
            .accessibilityLabel(Text("Everyday moves"))
            .accessibilityValue(
                Text("\(moves.done.count) of \(BrowserGettingStartedMove.allCases.count) done"))
        }
    }

    /// A move's check: an empty ring, filled with the guide's accent once
    /// the move is done.
    struct BrowserGettingStartedMoveCheck: View {
        let isDone: Bool
        let size: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(isDone ? AnyShapeStyle(OdeBrandTheme.accent) : AnyShapeStyle(.tertiary))
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.offUp, options: .nonRepeating))
                .animation(OdeMotion.collection, value: isDone)
                .accessibilityHidden(true)
        }
    }

    /// A move's default keys, one keycap each.
    struct BrowserGettingStartedKeys: View {
        let keys: String

        var body: some View {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    BrowserCommandPaletteKeycap { Text(verbatim: String(key)) }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Keys \(keys)"))
        }
    }

    /// The guide's card: the window's surface corner and a quiet material,
    /// opaque when transparency is reduced.
    private struct BrowserGettingStartedCardSurface: ViewModifier {
        @Environment(\.browserChromeAppearance) private var chromeAppearance
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: chromeAppearance.cornerScale.surface, style: .continuous)
            content
                .background {
                    if reduceTransparency {
                        shape.fill(OdeBrandTheme.surface)
                    } else {
                        shape.fill(.regularMaterial)
                    }
                }
                .overlay { shape.strokeBorder(OdeBrandTheme.line) }
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
    }

#endif
