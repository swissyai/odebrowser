import Foundation

/// Why Ode did not do what an agent asked, in words the agent's model reads
/// and can act on.
struct BrowserAgentFailure: Error, Sendable {
    // MARK: - Static Variables

    static let notAttached = Self("The helper has not introduced the agent yet.")
    static let unidentified = Self("Ode couldn’t tell which program this agent is.")
    static let declined = Self("The person didn’t allow this agent to use Ode.")
    static let historyKept = Self("The person kept this history.")
    static let windowDeclined = Self("The person didn’t let this agent open a window.")
    static let busy = Self("Ode is already asking the person about agents. Try again shortly.")
    static let noWindow = Self(
        "Ode could not open a browser window.")
    static let unsupportedAddress = Self("Agents may open only http and https addresses.")
    static let noPage = Self("The tab’s page could not be loaded.")
    static let cancelled = Self(
        "Cancellation observed. Subsequent cooperative work stopped; already submitted effects may continue.",
        outcome: .cancelled)
    static let navigationBoundaryUnavailable = Self(
        "unsupported: Agent page operations require a WebKit-only engine roster with pre-request navigation approval. "
            + "They are unavailable when Chromium or another engine is registered, including on loaded WebKit tabs.",
        outcome: .unsupported, effect: .notAttempted, refusal: .navigationBoundaryUnavailable)
    static let screenshotUnavailable = Self(
        "unsupported: Agent screenshots are unavailable because the engine cannot guarantee protected-field redaction "
            + "inside every frame and closed shadow root. Use take_snapshot or read_page instead.",
        outcome: .unsupported, effect: .notAttempted, refusal: .screenshotRedactionUnavailable)
    static let timedOut = Self(
        "The page took too long to answer. Effects may have occurred; reconcile the tab before repeating an action.",
        outcome: .unconfirmed)
    static let inputUnconfirmed = Self(
        "Ode did not receive an input acknowledgement. The input may have taken effect; "
            + "reconcile the tab before repeating the action.", outcome: .unconfirmed)
    static let scriptsOff = Self(
        "The person hasn’t allowed agents to run scripts in pages. They can allow it in Ode’s Settings › Agents.",
        outcome: .refused, effect: .notAttempted, refusal: .scriptsDisabled)
    static let pinnedOrSaved = Self("Agents may close only open tabs, never pinned or saved ones.")
    static let notEditable = Self("That element isn’t a text field, text area, editable element or menu.")
    static let notWebPage = Self(
        "The tab shows a browser or extension page, or a file, which agents can’t use. Open a web page instead.")
    static let tooLarge = Self(
        "The answer was too large to send. Effects may have occurred; reconcile before repeating an action. "
            + "For reads, ask for less, such as one element or the viewport.", outcome: .unconfirmed)

    // MARK: - Variables

    let message: String
    let outcome: AgentToolOutcome
    let effect: AgentToolEffect
    let refusal: AgentToolRefusal?

    var result: AgentToolResult { .error(message, outcome: outcome, effect: effect, refusal: refusal) }

    // MARK: - Initializers

    init(
        _ message: String, outcome: AgentToolOutcome = .failed, effect: AgentToolEffect = .unknown,
        refusal: AgentToolRefusal? = nil
    ) {
        self.message = message
        self.outcome = outcome
        self.effect = effect
        self.refusal = refusal
    }

    // MARK: - Actions - Failures

    static func checkCancellation() throws(Self) {
        if Task.isCancelled { throw .cancelled }
    }

    static func rejected(_ rejection: Rejection) -> Self {
        Self(rejection.explanation, outcome: .refused)
    }

    static func unknownTool(_ name: String) -> Self {
        Self("Ode has no tool named \(name).")
    }

    static func invalidArguments(_ detail: String) -> Self {
        Self("The arguments are not valid: \(detail)")
    }

    static func unknownElement(_ uid: String) -> Self {
        Self("The page has no element \(uid) now. Take a new snapshot and use its uids.")
    }

    static func spaceLocked(_ name: String) -> Self {
        Self("The \(name) Space is locked. Ask the person to unlock it in Ode.")
    }

    static func script(_ message: String) -> Self {
        Self("The script threw: \(message)")
    }

    /// The person hasn't allowed the session to open `origin`; the bar of
    /// the tab asks them.
    static func gateRequired(origin: String) -> Self {
        Self(
            "gate_required: Ode asks the person before you open \(origin), in the tab’s bar. "
                + "Wait for the person’s decision, then make the same call again.",
            outcome: .refused, refusal: .originApprovalRequired)
    }

    /// As `gateRequired`, for an agent that uses no tab whose bar could ask.
    static func gateRequiredWithoutTab(origin: String) -> Self {
        Self(
            "gate_required: Ode asks the person before you open \(origin), in the bar of a tab you use, "
                + "and you use none yet. Use a tab first, such as with show_tab on one from list_tabs, "
                + "then make the same call again and wait for the person’s decision.",
            outcome: .refused, refusal: .originApprovalRequired)
    }

    /// The page is showing `asked`, which holds up its scripts until someone
    /// answers it.
    static func dialog(_ asked: ScriptDialogAsked) -> Self {
        let message = String(asked.question.message.prefix(500))
        return asked.question.kind == .beforeUnload
            ? Self("The page is asking the person whether to leave it. Wait for them to answer.")
            : Self("The page is showing a dialog: “\(message)”. Answer it with handle_dialog.")
    }

    static func refused(_ detail: String) -> Self {
        Self(detail, outcome: .refused)
    }
}
