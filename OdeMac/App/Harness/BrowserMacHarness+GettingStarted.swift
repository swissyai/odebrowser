#if DEBUG || ODE_REVIEW_BUILD

    import AppKit

    /// The harness's Getting Started commands: open the guide at one of the
    /// everyday moves, and mark moves done as making them would.
    extension BrowserMacHarness {
        // MARK: - Actions - Getting Started

        /// Opens Getting Started on the everyday move `move`, as Help >
        /// Getting Started with Ode does, and marks the moves `done` names.
        func showGettingStartedMove(_ arguments: [String: Any]) throws -> [String: Any] {
            guard let moves = shell.application?.gettingStartedMoves else {
                throw Failure(description: "The browser is not running")
            }
            if arguments["reset"] as? Bool == true { moves.reset() }
            for name in arguments["done"] as? [String] ?? [] {
                guard let move = BrowserGettingStartedMove(rawValue: name) else {
                    throw Failure(description: "No everyday move is named \(name)")
                }
                moves.record(move)
            }
            shell.openGettingStarted()
            if let name = arguments["move"] as? String {
                guard let move = BrowserGettingStartedMove(rawValue: name) else {
                    throw Failure(description: "No everyday move is named \(name)")
                }
                moves.requestedMove = move
            }
            return ["done": moves.done.map(\.rawValue).sorted()]
        }

        /// Draws the everyday moves as Getting Started shows them, on `move`,
        /// in a window titled "Everyday Moves" that `snapshotWindow` can draw;
        /// a guide inside a tab sits in a scroll view the snapshot can't reach.
        func showEverydayMoves(_ arguments: [String: Any]) throws -> [String: Any] {
            guard let moves = shell.application?.gettingStartedMoves else {
                throw Failure(description: "The browser is not running")
            }
            let move = (arguments["move"] as? String).flatMap(BrowserGettingStartedMove.init(rawValue:))
            let wide = arguments["wide"] as? Bool ?? true
            return show(
                BrowserGettingStartedMovesStage(
                    moves: moves, selection: .constant(move), wide: wide, runCommand: { _ in true }
                )
                .padding(OdeSpacing.large)
                .background(OdeBrandTheme.canvas),
                titled: "Everyday Moves", width: wide ? 960 : 480)
        }
    }

#endif
